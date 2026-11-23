output "master_name" {
  value = local.master_name
}

output "master_public_ip" {
  value = google_compute_instance.node[local.master_name].network_interface[0].access_config[0].nat_ip
}

output "nodes" {
  description = "Nom => IP privée de chaque nœud."
  value       = { for n, v in local.nodes : n => v.ip }
}

output "boot_image" {
  description = "Image OS réellement utilisée : à reporter dans image_name au moment du tag v1.0."
  value       = local.boot_image
}

output "resolved_image_name" {
  value = data.google_compute_image.os.name
}
