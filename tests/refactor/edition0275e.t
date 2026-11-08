## fix --edition rust (0.27.5): std::fs's rows, from std2's fs (std2275):
## fs::exists, fs::append, fs::copy and Metadata::modified, whose std2
## forms differ from MVS's. Written, then built and run in the rust
## edition with the MVS program's output.
$ main.vl -o mvs
ok: built mvs
% ./mvs
true false 4
true true
4 true
$ fix --edition rust --list-left main.vl
fixed, 1 var to 'let mut', 1 integer annotated, 13 std calls by rewrite.tsv, 1 text view to &str	main.vl	+13 -12 lines
% cat main.vl
// fix --edition rust (0.27.5): std::fs's calls that change in std2, by
// rewrite.tsv: exists (an io::Result<bool>), append (none in Rust: an
// OpenOptions in append mode), copy (a u64), Metadata::modified (a
// SystemTime, MVS's the Duration since the epoch), DirEntry::is_file (its
// FileType's); a path given as bytes is `str::from_utf8(p).unwrap()`.
use std::fs;

fn main(gpa: Gpa) {
    let p = "f.txt";
    let q = "g.txt";
    fs::write(p, "ab").ok().unwrap();
    std::fs::OpenOptions::new().append(true).create(true).open(p).and_then(|mut f| std::io::Write::write_all(&mut f, "cd".as_ref())).ok().unwrap();
    let n = std::fs::copy(p, q).map(|n| n as i64).ok().unwrap();
    println("{} {} {}", std::fs::exists(q).unwrap_or(false), std::fs::exists("/nonexistent/x").unwrap_or(false), n);
    let pb: &str = "g.txt";
    let mut files: i64 = 0;
    match fs::read_dir(".") {
        Result::Ok(it) => {
            for e in it {
                match e {
                    Result::Ok(x) => {
                        if x.file_type().map(|t| t.is_file()).unwrap_or(false) {
                            files += 1;
                        }
                    }
                    Result::Err(_) => {}
                }
            }
        }
        Result::Err(_) => {}
    }
    println("{} {}", std::fs::exists(pb).unwrap_or(false), files > 1);
    let m = fs::metadata(q).ok().unwrap();
    println("{} {}", m.len(), m.modified().unwrap().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs() > 1000);
    fs::remove_file(p).ok().unwrap();
    fs::remove_file(q).ok().unwrap();
}
// EDITION: rust
$ main.vl -o prog
ok: built prog
% ./prog
true false 4
true true
4 true
