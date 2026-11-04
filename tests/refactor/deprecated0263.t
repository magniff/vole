## 0.26.3: `#[deprecated]` (Rust's), on a function, a struct, a field, a
## method and a constant: each use is warning item.deprecated with the
## item's note, through a `use` too (the import, then the name); a
## derived impl's names are the item's own.
$ check
main.vl:34:8: warning[item.deprecated] use of deprecated function 'old_fn': use new_fn | help: marked #[deprecated] at main.vl:3:9
main.vl:36:12: warning[item.deprecated] use of deprecated struct 'OldPoint': use Point | help: marked #[deprecated] at main.vl:12:9
main.vl:41:13: warning[item.deprecated] use of deprecated function 'old_fn': use new_fn | help: marked #[deprecated] at main.vl:3:9
main.vl:42:13: warning[item.deprecated] use of deprecated function 'old_fn': use new_fn | help: marked #[deprecated] at main.vl:3:9
main.vl:43:20: warning[item.deprecated] use of deprecated field 'P.x': use y | help: marked #[deprecated] at main.vl:19:9
main.vl:44:15: warning[item.deprecated] use of deprecated field 'P.x': use y | help: marked #[deprecated] at main.vl:19:9
main.vl:44:21: warning[item.deprecated] use of deprecated method 'P::get' | help: marked #[deprecated] at main.vl:25:13
main.vl:45:13: warning[item.deprecated] use of deprecated struct 'OldPoint': use Point | help: marked #[deprecated] at main.vl:12:9
main.vl:46:49: warning[item.deprecated] use of deprecated constant 'OLD' | help: marked #[deprecated] at main.vl:31:9
ok: 0 errors, 9 warnings in main.vl
$ explain item.deprecated
item.deprecated: warning
(0.26.3) A use of an item marked `#[deprecated]` (Rust's attribute: `#[deprecated]`, `#[deprecated = "note"]`, `#[deprecated(since = "1.2", note = "use new_fn")]`), on a function, a method, a struct, an enum, a trait, a type alias, a constant, a static or a field: a call, a name, a type, a path, a `use`, a field read or a struct literal's field. The message gives the item's note; the help, where it is marked. A use inside a deprecated item (a recursive call, a derived impl, a deprecated method reading a deprecated field) is not one, as in Rust, and std's uses of its own deprecated items are std's.
fix: Do what the note says (it names what to use instead); for std's `Buf`, `volec fix --only buf` rewrites each binding to `String<A>` (text) or `Vec<u8, A>` (bytes).
example:
    warning[item.deprecated] use of deprecated function 'old_fn': use new_fn | help: marked #[deprecated] at main.vl:2:5
