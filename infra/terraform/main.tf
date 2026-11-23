locals {
  name = var.cluster_name

  master_name = "${local.name}-master"

  # Un nœud = une VM + un disque de données dédié (/data).
  nodes = merge(
    {
      (local.master_name) = {
        role         = "master"
        ip           = cidrhost(var.subnet_cidr, 10)
        machine_type = var.master_machine_type
        data_disk_gb = var.master_data_disk_gb
      }
    },
    {
      for i in range(var.worker_count) : "${local.name}-worker-${i + 1}" => {
        role         = "worker"
        ip           = cidrhost(var.subnet_cidr, 11 + i)
        machine_type = var.worker_machine_type
        data_disk_gb = var.worker_data_disk_gb
      }
    }
  )

  labels = {
    project = "compression-bench"
    owner   = lower(var.owner)
  }

  boot_image = var.image_name != "" ? "projects/${var.image_project}/global/images/${var.image_name}" : data.google_compute_image.os.self_link
}

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

data "google_compute_image" "os" {
  family  = var.image_family
  project = var.image_project

  depends_on = [google_project_service.compute]
}

# ---------------------------------------------------------------------------
# Réseau : un VPC isolé, une zone unique (latence intra-cluster homogène).
# ---------------------------------------------------------------------------

resource "google_compute_network" "vpc" {
  name                    = "${local.name}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${local.name}-subnet"
  network       = google_compute_network.vpc.id
  region        = var.region
  ip_cidr_range = var.subnet_cidr
}

resource "google_compute_firewall" "internal" {
  name    = "${local.name}-allow-internal"
  network = google_compute_network.vpc.name

  source_ranges = [var.subnet_cidr]

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }
}

# Seul SSH est exposé, et seulement aux IP de l'équipe. Les UIs (HDFS, YARN,
# Spark, Prometheus, Grafana) passent par un tunnel SSH (`make tunnel`).
resource "google_compute_firewall" "ssh" {
  name    = "${local.name}-allow-ssh"
  network = google_compute_network.vpc.name

  source_ranges = var.admin_cidrs
  target_tags   = [local.name]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# ---------------------------------------------------------------------------
# Disques de données séparés du disque système : HDFS et le shuffle Spark
# écrivent sur /data, ce qui permet de mesurer leurs I/O sans le bruit de l'OS.
# ---------------------------------------------------------------------------

resource "google_compute_disk" "data" {
  for_each = local.nodes

  name   = "${each.key}-data"
  type   = var.data_disk_type
  size   = each.value.data_disk_gb
  zone   = var.zone
  labels = local.labels

  depends_on = [google_project_service.compute]
}

resource "google_compute_instance" "node" {
  for_each = local.nodes

  name             = each.key
  machine_type     = each.value.machine_type
  zone             = var.zone
  min_cpu_platform = var.min_cpu_platform
  tags             = [local.name]
  labels           = merge(local.labels, { role = each.value.role })

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = local.boot_image
      size  = var.boot_disk_gb
      type  = "pd-balanced"
    }
  }

  attached_disk {
    source      = google_compute_disk.data[each.key].id
    device_name = "data" # => /dev/disk/by-id/google-data
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    network_ip = each.value.ip

    access_config {} # IP publique éphémère (moins cher qu'un Cloud NAT)
  }

  # VMs standard uniquement : une VM Spot peut être arrêtée en plein run.
  scheduling {
    provisioning_model  = "STANDARD"
    preemptible         = false
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  metadata = {
    ssh-keys       = "${var.ssh_user}:${trimspace(file(var.ssh_public_key_path))}"
    enable-oslogin = "FALSE"
  }
}

# ---------------------------------------------------------------------------
# Inventaire Ansible généré automatiquement.
# ---------------------------------------------------------------------------

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory/hosts.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/inventory.tftpl", {
    master = {
      name       = local.master_name
      public_ip  = google_compute_instance.node[local.master_name].network_interface[0].access_config[0].nat_ip
      private_ip = local.nodes[local.master_name].ip
    }
    workers = [
      for n, v in local.nodes : {
        name       = n
        public_ip  = google_compute_instance.node[n].network_interface[0].access_config[0].nat_ip
        private_ip = v.ip
      } if v.role == "worker"
    ]
    ssh_user             = var.ssh_user
    ssh_private_key_path = var.ssh_private_key_path
    machine_type_master  = var.master_machine_type
    machine_type_worker  = var.worker_machine_type
  })
}
