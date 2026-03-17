///|
/// Benchmarks for plan refactor bottlenecks.
/// Run with: moon bench --target native -p trkbt10/indexion/cmd/indexion/plan/refactor

///|
/// Generate synthetic files and pairs for benchmarking.
fn gen_test_files(n : Int) -> Array[(String, String)] {
  let files : Array[(String, String)] = []
  for i = 0; i < n; i = i + 1 {
    let name = "src/pkg" + i.to_string() + "/file.mbt"
    let content = gen_test_content(i, 50)
    files.push((name, content))
  }
  files
}

///|
fn gen_test_content(seed : Int, lines : Int) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < lines; i = i + 1 {
    buf.write_string("fn func_")
    buf.write_string(((seed * 7 + i) % 100).to_string())
    buf.write_string("(x : Int) -> Int { x + ")
    buf.write_string(i.to_string())
    buf.write_string(" }\n")
  }
  buf.to_string()
}

///|
/// Generate pairs above threshold (simulating real scenario).
fn gen_test_pairs(
  files : Array[(String, String)],
  count : Int,
) -> Array[SimilarPair] {
  let pairs : Array[SimilarPair] = []
  let n = files.length()
  let mut added = 0
  for i = 0; i < n && added < count; i = i + 1 {
    for j = i + 1; j < n && added < count; j = j + 1 {
      pairs.push({
        file1: files[i].0,
        file2: files[j].0,
        similarity: 0.7 + ((i + j) % 30).to_double() / 100.0,
      })
      added = added + 1
    }
  }
  pairs
}

///|
/// Benchmark find_clusters with 100 files / 2000 pairs.
test "find_clusters_100f_2000p" (b : @bench.T) {
  let files = gen_test_files(100)
  let pairs = gen_test_pairs(files, 2000)
  b.bench(name="find_clusters_100f_2000p", fn() {
    b.keep(find_clusters(files, pairs, 0.7))
  })
}

///|
/// Benchmark find_clusters with 300 files / 8000 pairs (real-world scale).
test "find_clusters_300f_8000p" (b : @bench.T) {
  let files = gen_test_files(300)
  let pairs = gen_test_pairs(files, 8000)
  b.bench(name="find_clusters_300f_8000p", fn() {
    b.keep(find_clusters(files, pairs, 0.7))
  })
}

///|
/// Benchmark find_duplicate_blocks with two 50-line files.
test "find_duplicate_blocks_50lines" (b : @bench.T) {
  let content1 = gen_test_content(0, 50)
  let content2 = gen_test_content(0, 50) // identical content
  b.bench(name="find_dup_50lines", fn() {
    b.keep(find_duplicate_blocks(content1, content2, 5))
  })
}

///|
/// Benchmark find_duplicate_blocks with two 200-line files.
test "find_duplicate_blocks_200lines" (b : @bench.T) {
  let content1 = gen_test_content(0, 200)
  let content2 = gen_test_content(0, 200)
  b.bench(name="find_dup_200lines", fn() {
    b.keep(find_duplicate_blocks(content1, content2, 5))
  })
}

///|
/// Benchmark build_refactor_plan with real-scale data.
test "build_refactor_plan_3clusters" (b : @bench.T) {
  let files = gen_test_files(100)
  let pairs = gen_test_pairs(files, 2000)
  let clusters = find_clusters(files, pairs, 0.7)
  let config = RefactorPlanConfig::default()
  let file_contents : Map[String, String] = {}
  for f in files {
    file_contents.set(f.0, f.1)
  }
  b.bench(name="build_plan_3clusters", fn() {
    b.keep(build_refactor_plan(clusters, config, file_contents))
  })
}
