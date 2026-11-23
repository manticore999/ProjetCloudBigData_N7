"""Vérifie que chaque codec fonctionne réellement sur le cluster.

    spark-submit codec_check.py storage   # écrit/relit CSV et Parquet avec chaque codec
    spark-submit --conf spark.shuffle.compress=true \
                 --conf spark.io.compression.codec=zstd codec_check.py shuffle

Ce n'est PAS une mesure de performance : seulement un test de bon fonctionnement
(les tailles et durées affichées servent de contrôle de cohérence).
"""
import sys
import time

from pyspark.sql import SparkSession, functions as F

BASE = "hdfs:///tmp/codec-check"

# Codecs Hadoop pour les formats texte (noms de classes complets : non ambigus).
TEXT_CODECS = {
    "none": "none",
    "gzip": "org.apache.hadoop.io.compress.GzipCodec",
    "snappy": "org.apache.hadoop.io.compress.SnappyCodec",
    "lz4": "org.apache.hadoop.io.compress.Lz4Codec",
    "zstd": "org.apache.hadoop.io.compress.ZStandardCodec",
}
PARQUET_CODECS = ["none", "snappy", "gzip", "lz4_raw", "zstd"]


def sample(spark):
    # Données texte modérément compressibles, déterministes.
    return spark.range(0, 2_000_000).select(
        (F.col("id") % 1000).alias("k"),
        F.concat_ws(
            " ",
            F.lit("order"),
            (F.col("id") % 97).cast("string"),
            F.substring(F.sha2(F.col("id").cast("string"), 256), 1, 12),
        ).alias("v"),
    )


def hdfs_size(spark, path):
    jvm = spark.sparkContext._jvm
    conf = spark.sparkContext._jsc.hadoopConfiguration()
    p = jvm.org.apache.hadoop.fs.Path(path)
    return p.getFileSystem(conf).getContentSummary(p).getLength()


def check_storage(spark):
    df = sample(spark).cache()
    expected = df.count()
    ok = True
    for fmt, codecs in (("csv", TEXT_CODECS), ("parquet", {c: c for c in PARQUET_CODECS})):
        baseline = None
        for name, codec in codecs.items():
            path = f"{BASE}/{fmt}-{name}"
            try:
                t0 = time.time()
                df.write.mode("overwrite").option("compression", codec).format(fmt).save(path)
                t1 = time.time()
                n = spark.read.format(fmt).load(path).count()
                t2 = time.time()
                size = hdfs_size(spark, path)
                baseline = baseline or size
                status = "OK" if n == expected else f"FAIL rows={n} attendu={expected}"
                ok &= n == expected
                print(f"CHECK storage fmt={fmt:<7} codec={name:<7} bytes={size:>10} "
                      f"ratio={baseline / size:5.2f} write_s={t1 - t0:5.1f} read_s={t2 - t1:5.1f} {status}")
            except Exception as e:  # noqa: BLE001 — on veut voir tous les codecs en échec
                ok = False
                print(f"FAIL storage fmt={fmt} codec={name}: {str(e).splitlines()[0]}")
    return ok


def check_shuffle(spark):
    conf = spark.sparkContext.getConf()
    codec = conf.get("spark.io.compression.codec", "lz4")
    enabled = conf.get("spark.shuffle.compress", "true")
    t0 = time.time()
    groups = sample(spark).groupBy("k").agg(F.count("*").alias("n")).collect()
    ok = len(groups) == 1000 and sum(r["n"] for r in groups) == 2_000_000
    print(f"CHECK shuffle compress={enabled} codec={codec:<6} groups={len(groups)} "
          f"time_s={time.time() - t0:5.1f} {'OK' if ok else 'FAIL'}")
    return ok


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "storage"
    spark = SparkSession.builder.appName(f"codec-check-{mode}").getOrCreate()
    try:
        ok = check_storage(spark) if mode == "storage" else check_shuffle(spark)
    finally:
        spark.stop()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
