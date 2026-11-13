#!/bin/sh
# (0.18.1) The statics that code generation's tasks may write
# (docs/optimizer.md, "0.18.1: threads", "Why there is no data race"):
# the functions middle::parallel::run_task reaches (query callees
# --transitive) and, for every static of the compiler, its writes and
# borrows in them (query refs; a method call that changes it, X.push(..),
# and an address taken, &X, count) are listed, and each static found must
# be one below, with the reason it is no race. A new one fails: move it
# into middle::ctx::FnCtx, make it before the tasks run
# (parallel::prepare_tasks), or join it between phases. The same for the
# join (parallel::join_task: the assembler, beside the tasks): a static
# it writes that a task reads or writes must be one of JOINED below; and
# for -O0's assembler thread (objfile::assemble_bytes, beside gen0's code
# generation, gen_function and asm_hand_over on the main thread): a static
# one side writes that the other touches must be one of ASSEMBLER below.
#
# (0.18.1, T8) And every static task code touches (reads too) must be one
# of READ below, with how the code cache (back::codecache) covers it: a
# task's entry is used only when what it read is the same, so a static it
# reads must be in the key (the options, the program's types), recorded
# as read (a fact of another function, cc_note), part of the IR's hash, a
# mode the cache is off in, or the cache's own. A new one fails: say how
# its value reaches the key, or the cache uses outputs made from another.
#
# usage: tests/threads_writes.sh [-c COMPILER]

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/volec"
while [ $# -gt 0 ]; do
    case "$1" in
        -c) COMPILER=$2; shift 2 ;;
        *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    esac
done
case "$COMPILER" in /*) ;; *) COMPILER="$(pwd)/$COMPILER" ;; esac

# static <TAB> why it is no race
ALLOWED='middle::inline::FN_SIZE	the task'"'"'s own function'"'"'s entry; others read a lower level'"'"'s
middle::inline::FN_RT	the task'"'"'s own function'"'"'s entry (finish_component_function)
middle::inline::FN_DECIDERS_START	the task'"'"'s own function'"'"'s entry
middle::inline::FN_DECIDERS	the task'"'"'s own function'"'"'s entry
middle::opt::DEFERRED	the task'"'"'s own function'"'"'s entry
middle::ir::IRFUNCS	the task'"'"'s own function'"'"'s entry (ir_save, ir_free_func, tail recursion)
middle::ipo::FN_ATTRS	the task'"'"'s own component'"'"'s entries
middle::ipo::FN_NOCAPTURE	the task'"'"'s own component'"'"'s entries
middle::ipo::FN_ATTRS_DONE	the task'"'"'s own component'"'"'s entries
middle::parallel::COMP_GROWTH	the task'"'"'s own component'"'"'s entry, read between levels
middle::parallel::COMP_INLINED	the task'"'"'s own component'"'"'s entry, read between levels
middle::parallel::FN_CONSTS	the task'"'"'s own function'"'"'s list; others read its entries made in earlier phases, which never move (chunks)
middle::parallel::FN_TEXT	the task'"'"'s own function'"'"'s entry, read at the join
back::codecache::FN_IRH	the task'"'"'s own functions'"'"' entries; others read a lower level'"'"'s or an earlier phase'"'"'s (FN_IRH_OK)
back::codecache::FN_IRH_OK	the same
back::codecache::FN_STRS	the same
back::codecache::OUT_COMP	the task'"'"'s own component'"'"'s entry, read after the phases (the counts)
back::codecache::OUT_EMIT	the task'"'"'s own function'"'"'s entry, read after the phases
back::codecache::OUT_SCALAR	the task'"'"'s own function'"'"'s entry, read after the phases
back::codecache::SCALAR_REC	the task'"'"'s own function'"'"'s entry (its cleanup'"'"'s, then its scalar pipeline'"'"'s, a phase after)
back::codecache::pack::NEW	the task'"'"'s own slot, read when the pack is written
back::codecache::pack::USED	the entry of the task'"'"'s own key, read when the pack is written (0.27.8: a key is one task'"'"'s but a function'"'"'s that shares its symbol, fn_ambig, whose task does not mark it: mark_used)
base::ctx::Ctx.pack	read only: an entry'"'"'s body is read through its address
base::STRESS_GROW	read by prepare_tasks (stress_grow)
middle::egraph::P_KIND	the rules, parsed by prepare_tasks (init_rules)
middle::egraph::P_OP	the rules
middle::egraph::P_COND	the rules
middle::egraph::P_A	the rules
middle::egraph::P_B	the rules
middle::egraph::P_VAL	the rules
middle::egraph::R_LHS	the rules
middle::egraph::R_RHS	the rules
middle::egraph::R_GUARD	the rules
middle::egraph::R_VARS	the rules
middle::egraph::RULES_READY	the rules
middle::egraph::PT	the rules
middle::egraph::PP	the rules
middle::egraph::PVARS	the rules
middle::egraph::R_VARS_NOW	the rules
middle::egraph::R_BY_OP	the rules
middle::egraph::R_BY_OP_START	the rules
front::types::FIELDS	struct_field: a field'"'"'s address, read through in a task (the offsets are compute_layout'"'"'s, the main thread'"'"'s)
front::distinct::NICHE	enum_niche: every enum'"'"'s is made before a phase (prepare_layouts)
front::cells::FREEZE_MEMO	interior_part: every type'"'"'s Freeze fact is made before a phase (prepare_layouts), so a task only reads it (GVN'"'"'s param_class_of)
front::lexer::STRS	add_const_data: only on const_data'"'"'s serial branch (task_phase 0)
front::lexer::STR_COUNT	the same
gen0::target::STR_ALIGN	the same
front::lexer::STR_CAP	the same
back::dwarf::LINE_STARTS	-g, which runs on one thread (parallel::serial_only)
back::dwarf::SRC_END	-g
back::dwarf::FILE_NUMBERS	-g
back::dwarf::FILES_USED	-g
back::dwarf::DBG_FNS	-g
back::dwarf::DBG_PREFIX	-g
back::dwarf::DBG_POS	-g
base::CWD	-g (dbg_loc'"'"'s paths, out_path)
base::OUT_PATHS	-g
base::ROOT_DIR	-g
base::ROOT_LEX	-g
base::ROOT_LEX_ABS	-g
tools::query::checks::REMOVED	query checks (--print-checks), which runs on one thread
back::emit::stats::ST_ALL	--stats, which runs on one thread
base::timer::T_TOTALS	--time-passes, which runs on one thread (timer_add writes only then)
base::BUFS	a task writes its context'"'"'s buffers'"'"' entries; none is made in a task (buf_new: below)
base::BUF_CAP	buf_new, below
base::BUF_COUNT	buf_new: the printers of --stats, --print-regalloc, --print-after-all, --verify-* (one thread), and internal errors, which exit
base::diag::ERR_POISONED	the IR printers (one thread)'

# The join's writes that task code touches: static <TAB> why it is no race
JOINED='base::BUFS	the join writes the program'"'"'s buffers'"'"' entries, a task its context'"'"'s
middle::parallel::FN_CONSTS	the join numbers the joined function'"'"'s constants, which no running task reads
middle::parallel::FN_TEXT	the join takes the joined function'"'"'s text, its task done
base::BUF_COUNT	asm_error, which exits
base::BUF_CAP	asm_error, which exits
base::STRESS_GROW	read by prepare_tasks (stress_grow)
base::timer::T_TOTALS	--time-passes, which runs on one thread'

# The assembler thread's and -O0's main thread's: static <TAB> why
ASSEMBLER='base::BUFS	asm_error (an internal error, which exits) and dwarf_file (-g, which does not stream: no thread)
base::BUF_CAP	the same
base::BUF_COUNT	the same
base::STRESS_GROW	read by asm_thread_start before the thread starts (stress_grow)'
# (0.27.8) And per function: a static -O0's main thread writes while the
# assembler thread runs (gen0's messages grow BUFS: buf_new) that a
# function on the assembler's streaming path touches: static <TAB> function
# <TAB> why. The streaming path is what assemble_bytes reaches but through
# ASM_EXITS (an internal error, which exits; -g's DWARF, made where no
# thread streams). A new one fails: 0.27.7's insn_text read BUFS[INSN_BUF]
# as main grew BUFS (it reads INSN_TEXT now, a view taken before the thread
# starts).
ASM_EXITS='back::objfile::assemble::asm_error back::objfile::debug::dwarf_file'
ASM_READS='base::STRESS_GROW	base::stress_grow	set by asm_thread_start before the thread starts (stress_grow); main writes it only while it is unset
base::STRESS_GROW	base::get_stress_grow	(0.28.0) stress_grow'"'"'s read of it, the same
base::STRESS_GROW	base::set_stress_grow	(0.28.0) stress_grow'"'"'s write of it, the same: only while it is unset'

# Every static task code reads or writes: static <TAB> how the code cache
# covers it (key: in the entry's key; read: recorded, cc_note; IR: in
# hash::ir_hash; off: a mode the cache is off in, cc_wanted; own: the
# cache's, or the task's context's).
READ='base::SYMS_FROZEN	own: set by pool_run around every phase, the same in every task (no new symbol)
base::ctx::Ctx.time_instructions	off: --time-passes turns the cache off (cc_wanted), set by the options before the tasks
base::ctx::Ctx.perf_fd	off: the same; opened by counters_open on the main thread before the tasks, read-only after
base::ctx::Ctx.counters_off	off: the same (counters_open)
base::ctx::Ctx.time_each_pass	off: the same (--time-passes=passes), set by the options before the tasks
base::ctx::Ctx.pass_counts	off: the same; atomics a pass'"'"'s end adds to (timer::pass_done) only when time_each_pass, which runs on one thread (serial_only)
base::ctx::Ctx.vec_stats_fn	off: --vec-stats=FN is an option the cache does not know (ARGS_UNKNOWN), set by the options before the tasks
base::ctx::Ctx.static_named	output: none; the emission (materialize) reads it only to stop on an internal error, made by statics_named_by_ir before the tasks
base::ctx::Ctx.vec_tmpl	key: std'"'"'s Vec template, found in the program'"'"'s types (types_hash) by init_vec_facts before the tasks, read-only after
base::ctx::Ctx.wraps	key: the same (std'"'"'s Vec wrappers)
base::ctx::Ctx.a64_lse_flag	key: --atomics= is in the options hash (codecache::arg_kind), set by main before the tasks
base::ctx::Ctx.arch_used	key: a program naming std::arch has its intrinsics in its IR and the build features in the options hash (made by the front end, before the tasks)
base::ctx::Ctx.arch_word_sym	IR: set before the tasks (arch_after_lowering); a function reaches instruction selection with a CPUFEAT, which ir_hash covers, only in a program whose main fills std::ARCH_FEATURES, and the symbol is the same in every build
base::ctx::Ctx.intrs	key: the intrinsic tables are part of the compiler (its identity), parsed by the front end before the tasks, read-only after
base::ctx::Ctx.intr_count	key: the same
base::ctx::Ctx.table_buf	key: the same
base::ctx::Ctx.table_fields	key: the same
base::ctx::Ctx.params	key: the same
base::ctx::Ctx.build_features	key: the build'"'"'s features, made by main before the tasks (build_features), are in the options hash
base::ctx::Ctx.needs	IR: made by the front end before the tasks; read by LICM (intr_guarded) for the features of an INTR it may hoist, which follow from the function'"'"'s guards and calls: a guard or a declared set changes the IR (has/detect folded), an unguarded call'"'"'s needs are inferred whatever the declaration, an inlined callee'"'"'s INTRs are in the IR
base::ctx::Ctx.needs_count	IR: the same
base::ctx::Ctx.cc_on	own
base::ctx::Ctx.check	own (testing)
base::ctx::Ctx.codecache_env	own: the key'"'"'s program hash
back::codecache::FN_IRH	own: read R_IR
back::codecache::FN_IRH_OK	own
back::codecache::FN_STRS	own: the strings of a read IR
back::codecache::OUT_COMP	own
back::codecache::OUT_EMIT	own
back::codecache::OUT_SCALAR	own
back::codecache::SCALAR_REC	own: a function'"'"'s recording, from its cleanup to its scalar pipeline
base::ctx::Ctx.why	own (testing)
base::ctx::Ctx.fn_ambig	own
base::ctx::Ctx.fn_canon	own: what IR names a function by
base::ctx::Ctx.fn_moves	own: MOVE_COPIES, in the IR hash
base::ctx::Ctx.fn_nameh	own
base::ctx::Ctx.name_fn	own
base::ctx::Ctx.name_ir	own
base::ctx::Ctx.str_h	own: a string'"'"'s bytes
base::ctx::Ctx.str_h_count	own
base::ctx::Ctx.entry_at	own
base::ctx::Ctx.index	own
base::ctx::Ctx.index_size	own
back::codecache::pack::NEW	own
base::ctx::Ctx.new_slots	own
base::ctx::Ctx.pack	own
back::codecache::pack::USED	own
back::dwarf::DBG_FNS	off: -g
back::dwarf::DBG_POS	off: -g
back::dwarf::DBG_PREFIX	off: -g
base::ctx::Ctx.debug_info	off: -g
back::dwarf::FILES_USED	off: -g
back::dwarf::FILE_NUMBERS	off: -g
back::dwarf::LINE_STARTS	off: -g
back::dwarf::SRC_END	off: -g
base::ctx::Ctx.stats	off: --stats
back::emit::stats::ST_ALL	off: --stats
base::ctx::Ctx.print_regalloc	off: --print-regalloc
base::ctx::Ctx.verify_regalloc	off: --verify-regalloc
base::ctx::Ctx.x86_alloc_acd	key: options_hash
base::BUFS	own: the context'"'"'s buffers
base::BUF_CAP	own: buf_new on internal errors and printers
base::BUF_COUNT	own: the same
base::CWD	off: -g (out_path)
base::ctx::Ctx.files	off: -g (dbg_loc, out_path)
base::OUT_PATHS	off: -g
base::ROOT_DIR	off: -g
base::ROOT_LEX	off: -g
base::ROOT_LEX_ABS	off: -g
base::SRC	off: -g
base::STDOUT_CAPTURE	own: messages
base::STRESS_GROW	key: options_hash (stress_grow)
base::ctx::Ctx.syms	IR: a symbol by its text
base::ctx::Ctx.sym_table	IR: the same
base::ctx::Ctx.sym_table_size	IR: the same
base::diag::ERR_POISONED	off: the IR printers
base::json::DIAG_JSON	own: messages
base::ctx::Ctx.apple_a64	key: options_hash
base::target::ELF	key: options_hash
base::target::X86	key: options_hash
base::ctx::Ctx.time_passes	off: --time-passes
base::timer::T_TOTALS	off: --time-passes
base::ctx::Ctx.nodes	IR: a closure'"'"'s mark (fn_canon), a distinct type'"'"'s name (types_hash); -g
base::ctx::Ctx.locals	own: a task makes variables above LOCAL_COUNT (ssa::new_synth_var), never reads a local'"'"'s (locals.len(): the same)
base::ctx::Ctx.any_distinct	key: options_hash
front::distinct::NICHE	key: types_hash (enum_niche)
base::ctx::Ctx.niche_aliases	key: types_hash
front::cells::FREEZE_MEMO	key: types_hash (each type'"'"'s is_freeze)
front::cells::SYM_UNSAFE_CELL	key: the same
base::ctx::Ctx.modules	key: the same (is_within, only from is_freeze: whether a struct is std'"'"'s UnsafeCell)
base::ctx::Ctx.std_module	key: the same (within_std)
base::ctx::Ctx.fn_effects	IR: a function'"'"'s effects (fn_canon)
base::ctx::Ctx.fn_effects_count	IR: the same
front::effects::builtin::TABLE	IR: by a symbol'"'"'s text; the same in every build of a compiler
front::lexer::STRS	IR: a string'"'"'s bytes (STR_H)
front::lexer::STR_CAP	IR: the same (no string is made in a task)
front::lexer::STR_COUNT	IR: the same
base::ctx::Ctx.edition	key: options_hash (0.27.1: a rust body gets no parameter alias facts, gvn noalias_active)
base::ctx::Ctx.borrowck_verdict	fact: R_ATTRS mixes the verdict in; 0.27.1, gvn noalias_active asks it of a rust body, set per body before the tasks by places/borrowck
front::types::ENUMS	key: types_hash
front::types::FIELDS	key: types_hash
base::ctx::Ctx.fns	IR: a function by fn_canon
base::ctx::Ctx.statics	IR: a static by static_canon
base::ctx::Ctx.structs	key: types_hash
base::ctx::Ctx.sym_static	IR: the same
base::ctx::Ctx.tlists	key: types_hash
base::ctx::Ctx.types	key: types_hash
base::ctx::Ctx.type_hash	key: types_hash
base::ctx::Ctx.type_hash_size	key: types_hash
base::ctx::Ctx.ty_error	key: types_hash (a fixed id)
base::ctx::Ctx.ty_v16i8	key: types_hash (a fixed id)
base::ctx::Ctx.ty_v2f64	key: types_hash (a fixed id)
base::ctx::Ctx.ty_v2i64	key: types_hash (a fixed id)
base::ctx::Ctx.ty_v4f32	key: types_hash (a fixed id)
base::ctx::Ctx.ty_v4i32	key: types_hash (a fixed id)
base::ctx::Ctx.ty_v8i16	key: types_hash (a fixed id)
base::ctx::Ctx.variants	key: types_hash
base::ctx::Ctx.main_sym	IR: a symbol by its text
base::ctx::Ctx.link_names	IR: fn_canon
gen0::target::RT_PANIC_SYM	IR: a symbol by its text
gen0::target::RT_NOTE_SYM	IR: a symbol by its text
gen0::target::STR_ALIGN	IR: a string'"'"'s alignment (STR_H)
base::ctx::Ctx.move_copies	IR: FN_MOVES
base::ctx::Ctx.egraph	key: options_hash
middle::egraph::PP	own: the rules, the same in every build of a compiler
middle::egraph::PT	own: the same
middle::egraph::PVARS	own: the same
middle::egraph::P_A	own: the same
middle::egraph::P_B	own: the same
middle::egraph::P_COND	own: the same
middle::egraph::P_KIND	own: the same
middle::egraph::P_OP	own: the same
middle::egraph::P_VAL	own: the same
middle::egraph::RULES_READY	own: the same
middle::egraph::R_BY_OP	own: the same
middle::egraph::R_BY_OP_START	own: the same
middle::egraph::R_GUARD	own: the same
middle::egraph::R_LHS	own: the same
middle::egraph::R_RHS	own: the same
middle::egraph::R_VARS	own: the same
middle::egraph::R_VARS_NOW	own: the same
middle::gvn::MEMCPY_SYM	IR: a symbol by its text
base::ctx::Ctx.noalias_off	key: options_hash
base::ctx::Ctx.ifconv	key: options_hash
base::ctx::Ctx.fn_address	read: R_STATIC (facts_fixed); the key (own_fp)
base::ctx::Ctx.fn_calls	read: R_CALLS, whether one is left
middle::inline::FN_DECIDERS	read: R_DEC
middle::inline::FN_DECIDERS_START	read: R_DEC
base::ctx::Ctx.fn_live	read: R_STATIC; the key
middle::inline::FN_RT	read: R_RT
base::ctx::Ctx.fn_scc	read: R_STATIC, whether in the task'"'"'s SCC
middle::inline::FN_SIZE	read: R_SIZE; the key
base::ctx::Ctx.leaf_done	read: R_STATIC; the key
base::ctx::Ctx.leaf_keep	read: R_STATIC; the key
base::ctx::Ctx.leaf_small	read: R_STATIC; the key
base::ctx::Ctx.program_budget	read: R_BUDGET, whether within
base::ctx::Ctx.program_size	read: R_BUDGET
base::ctx::Ctx.scc_order	key: the component'"'"'s functions
base::ctx::Ctx.attrs_ready	key: cc_phase
middle::ipo::CALLOC_SYM	IR: a symbol by its text
middle::ipo::FN_ATTRS	read: R_ATTRS; the key
middle::ipo::FN_ATTRS_DONE	read: R_ATTRS, R_STATIC (ready); the key
middle::ipo::FN_NOCAPTURE	read: R_ATTRS; the key
middle::ipo::FREE_SYM	IR: a symbol by its text
middle::ipo::MALLOC_SYM	IR: a symbol by its text
base::ctx::Ctx.fn_ir	IR: fn_canon (whether it has IR)
middle::ir::IRFUNCS	IR: the task'"'"'s own; read: R_IR, another'"'"'s
base::ctx::Ctx.fn_rtids	IR: an RTID value by its function and place, its class (the number is the join'"'"'s)
base::ctx::Ctx.irfunc_count	own
base::ctx::Ctx.ir_call_locs	off: --trace
base::ctx::Ctx.ir_expr_loc	off: -g and --trace (IR_LOCS)
base::ctx::Ctx.ir_loc	off: the same
base::ctx::Ctx.ir_locs	off: the same
base::ctx::Ctx.print_after_all	off: --print-after-all
base::ctx::Ctx.verify_ir	off: --verify-ir
middle::opt::DEFERRED	the key (own_fp)
base::ctx::Ctx.opt_level	key: options_hash
base::ctx::Ctx.per_function	key: options_hash
base::ctx::Ctx.comp_end	key: the component'"'"'s functions
middle::parallel::COMP_GROWTH	own: an output
middle::parallel::COMP_INLINED	own: an output
base::ctx::Ctx.comp_level	read: R_STATIC (ready)
base::ctx::Ctx.comp_of	read: R_STATIC (ready)
base::ctx::Ctx.comp_start	key: the component'"'"'s functions
middle::parallel::FN_CONSTS	IR: constant data by owner, place and bytes (const_canon); outputs
middle::parallel::FN_TEXT	own: an output
base::ctx::Ctx.fresh_contexts	key: options_hash (cc_args: $VOLE_FRESH_CONTEXTS)
base::ctx::Ctx.parallel_items	own: the task'"'"'s function
base::ctx::Ctx.profile_max	off: --profile-use (and options_hash)
base::ctx::Ctx.slp	key: options_hash
base::ctx::Ctx.vectorize	key: options_hash
base::ctx::Ctx.unroll_runtime	key: options_hash
base::ctx::Ctx.print_checks	off: --print-checks
tools::query::checks::REMOVED	off: --print-checks'

cd "$ROOT" || exit 1
WORK="$ROOT/target/threads"
mkdir -p "$WORK"
# The functions a task reaches.
{
    echo "middle::parallel::run_task"
    "$COMPILER" query callees crate::middle::parallel::run_task --transitive --all | awk -F'\t' 'NF >= 3 { print $3 }'
} | sort -u >"$WORK/reached"
[ -s "$WORK/reached" ] || { echo "threads-writes: query callees found nothing"; exit 1; }
# Every static, as a query path.
# (0.25.5: `static var`, as statics are spelled now; `static mut` matched
# nothing, and the checks passed on no static at all)
grep -rn --exclude-dir=.volec '^ *\(pub \)\{0,1\}static \(mut\|var\) [A-Za-z_0-9]* *:' compiler/src | awk -F: '{
    file = $1; sub(/^compiler\/src\//, "", file); sub(/\.vl$/, "", file); sub(/\/mod$/, "", file)
    gsub(/\//, "::", file)
    line = $0; sub(/^[^:]*:[^:]*:/, "", line)
    sub(/^ *(pub )?static (mut|var) /, "", line); sub(/ *:.*/, "", line)
    print (file == "main" ? "crate" : "crate::" file) "::" line
}' >"$WORK/statics"
# (0.26.5) And every field of the compilation context, base::ctx::Ctx,
# which a task is lent let (middle::threads::run_pooled): its statics
# moved there keep their entries below, as base::ctx::Ctx.FIELD.
awk '/^pub struct Ctx</ { on = 1; next } on && /^}/ { on = 0 }
    on && /^    pub [a-z_0-9]+:/ { f = $2; sub(/:.*/, "", f); print "crate::base::ctx::Ctx." f }' \
    compiler/src/base/ctx.vl >>"$WORK/statics"
sed 's/^/query refs /; s/$/ --all/' "$WORK/statics" | "$COMPILER" batch >"$WORK/refs" 2>&1
awk -F'\t' -v reached="$WORK/reached" '
    BEGIN { while ((getline f < reached) > 0) in_task[f] = 1 }
    /^## \$ volec query refs / { s = $0; sub(/^## \$ volec query refs crate::/, "", s); sub(/ --all$/, "", s); n = s; sub(/.*::/, "", n); sub(/.*\./, "", n); next }
    NF >= 4 && $1 ~ /^[0-9]+:[0-9]+$/ {
        w = ($2 == "write" || $2 == "borrow")
        # (a method that changes it, through an element too; an address
        # taken, &X or &X[i], which a write may go through)
        if ($2 == "read" && match($4, n "(\\[[^]]*\\])?[ \t]*\\.[ \t]*(push|pop|clear|set|insert|put|reserve|truncate|remove|append|extend)[ \t]*\\(")) w = 1
        if ($2 == "read" && match($4, "&(mut )?([A-Za-z_0-9]+\\.)*" n "([^A-Za-z_0-9]|$)")) w = 1
        if (w && ($3 in in_task)) print s
    }' "$WORK/refs" | sort -u >"$WORK/written"
printf '%s\n' "$ALLOWED" | cut -f1 | sort -u >"$WORK/allowed"
new=$(comm -23 "$WORK/written" "$WORK/allowed")
for s in $new; do
    echo "FAIL $s: a task writes it; try: $COMPILER query callees crate::middle::parallel::run_task --writes crate::$s"
done
# The join's.
{
    echo "middle::parallel::join_task"
    "$COMPILER" query callees crate::middle::parallel::join_task --transitive --all | awk -F'\t' 'NF >= 3 { print $3 }'
} | sort -u >"$WORK/joined"
awk -F'\t' -v joined="$WORK/joined" -v reached="$WORK/reached" '
    BEGIN {
        while ((getline f < joined) > 0) in_join[f] = 1
        while ((getline f < reached) > 0) in_task[f] = 1
    }
    /^## \$ volec query refs / { s = $0; sub(/^## \$ volec query refs crate::/, "", s); sub(/ --all$/, "", s); n = s; sub(/.*::/, "", n); sub(/.*\./, "", n); next }
    NF >= 4 && $1 ~ /^[0-9]+:[0-9]+$/ {
        w = ($2 == "write" || $2 == "borrow")
        if ($2 == "read" && match($4, n "(\\[[^]]*\\])?[ \t]*\\.[ \t]*(push|pop|clear|set|insert|put|reserve|truncate|remove|append|extend)[ \t]*\\(")) w = 1
        if ($2 == "read" && match($4, "&(mut )?([A-Za-z_0-9]+\\.)*" n "([^A-Za-z_0-9]|$)")) w = 1
        if (w && ($3 in in_join)) join_writes[s] = 1
        if ($2 != "use" && $2 != "def" && $2 != "init" && ($3 in in_task)) task_touches[s] = 1
    }
    END { for (s in join_writes) if (s in task_touches) print s }' "$WORK/refs" | sort -u >"$WORK/join-written"
printf '%s\n' "$JOINED" | cut -f1 | sort -u >"$WORK/join-allowed"
newj=$(comm -23 "$WORK/join-written" "$WORK/join-allowed")
for s in $newj; do
    echo "FAIL $s: the join writes it and a task uses it; try: $COMPILER query callees crate::middle::parallel::join_task --writes crate::$s"
done
# -O0's assembler thread against the main thread.
{
    echo "back::objfile::assemble_bytes"
    "$COMPILER" query callees crate::back::objfile::assemble_bytes --transitive --all | awk -F'\t' 'NF >= 3 { print $3 }'
} | sort -u >"$WORK/assembler"
# (0.26.2) gen0 generates every function from its kept body
# (gen_places_function; an atomic intrinsic's, gen_atomic_function); a
# name that is gone fails here, not by checking less.
GEN0_MAIN="gen0::gen::places::gen_places_function gen0::gen::gen_atomic_function back::objfile::asm_hand_over"
for f in $GEN0_MAIN; do
    "$COMPILER" query callees "crate::$f" >/dev/null 2>&1 \
        || { echo "threads-writes: no function $f (tests/threads_writes.sh GEN0_MAIN)"; exit 1; }
done
{
    printf '%s\n' $GEN0_MAIN
    "$COMPILER" query callees $(printf 'crate::%s ' $GEN0_MAIN) --transitive --all | awk -F'\t' 'NF >= 3 { print $3 }'
} | sort -u >"$WORK/gen0"
awk -F'\t' -v A="$WORK/assembler" -v M="$WORK/gen0" '
    BEGIN {
        while ((getline f < A) > 0) in_asm[f] = 1
        while ((getline f < M) > 0) in_main[f] = 1
    }
    /^## \$ volec query refs / { s = $0; sub(/^## \$ volec query refs crate::/, "", s); sub(/ --all$/, "", s); n = s; sub(/.*::/, "", n); sub(/.*\./, "", n); next }
    NF >= 4 && $1 ~ /^[0-9]+:[0-9]+$/ {
        w = ($2 == "write" || $2 == "borrow")
        if ($2 == "read" && match($4, n "(\\[[^]]*\\])?[ \t]*\\.[ \t]*(push|pop|clear|set|insert|put|reserve|truncate|remove|append|extend)[ \t]*\\(")) w = 1
        if ($2 == "read" && match($4, "&(mut )?([A-Za-z_0-9]+\\.)*" n "([^A-Za-z_0-9]|$)")) w = 1
        t = ($2 != "use" && $2 != "def" && $2 != "init")
        if ($3 in in_asm) { if (w) aw[s] = 1; if (t) at[s] = 1 }
        if ($3 in in_main) { if (w) mw[s] = 1; if (t) mt[s] = 1 }
    }
    END { for (s in aw) if (s in mt) print s; for (s in mw) if (s in at) print s }' "$WORK/refs" | sort -u >"$WORK/asm-shared"
printf '%s\n' "$ASSEMBLER" | cut -f1 | sort -u >"$WORK/asm-allowed"
newa=$(comm -23 "$WORK/asm-shared" "$WORK/asm-allowed")
for s in $newa; do
    echo "FAIL $s: -O0's assembler thread and its main thread share it; try: $COMPILER query callees crate::back::objfile::assemble_bytes --writes crate::$s"
done
# (0.27.8) Per function, against ASM_READS: the assembler's functions that
# touch a static the main thread writes meanwhile, those of them on its
# streaming path (reached from assemble_bytes, not through ASM_EXITS: their
# callers in the assembler, walked up level by level).
awk -F'\t' -v A="$WORK/assembler" -v M="$WORK/gen0" '
    BEGIN {
        while ((getline f < A) > 0) in_asm[f] = 1
        while ((getline f < M) > 0) in_main[f] = 1
    }
    /^## \$ volec query refs / { s = $0; sub(/^## \$ volec query refs crate::/, "", s); sub(/ --all$/, "", s); n = s; sub(/.*::/, "", n); sub(/.*\./, "", n); next }
    NF >= 4 && $1 ~ /^[0-9]+:[0-9]+$/ {
        w = ($2 == "write" || $2 == "borrow")
        if ($2 == "read" && match($4, n "(\\[[^]]*\\])?[ \t]*\\.[ \t]*(push|pop|clear|set|insert|put|reserve|truncate|remove|append|extend)[ \t]*\\(")) w = 1
        if ($2 == "read" && match($4, "&(mut )?([A-Za-z_0-9]+\\.)*" n "([^A-Za-z_0-9]|$)")) w = 1
        t = ($2 != "use" && $2 != "def" && $2 != "init")
        if (($3 in in_main) && w) mw[s] = 1
        if (($3 in in_asm) && t) touch[s "\t" $3] = 1
    }
    END { for (k in touch) { split(k, p, "\t"); if (p[1] in mw) print k } }' "$WORK/refs" | sort -u >"$WORK/asm-touch"
cut -f2 "$WORK/asm-touch" | sort -u >"$WORK/up-new"
: >"$WORK/up-seen"
: >"$WORK/up-edges"
while [ -s "$WORK/up-new" ]; do
    cat "$WORK/up-new" >>"$WORK/up-seen"
    sed 's/^/query callers crate::/; s/$/ --all/' "$WORK/up-new" | "$COMPILER" batch 2>&1 \
        | awk -F'\t' -v A="$WORK/assembler" -v exits="$ASM_EXITS" '
            BEGIN {
                while ((getline f < A) > 0) in_asm[f] = 1
                n = split(exits, e, " "); for (i = 1; i <= n; i++) cut[e[i]] = 1
            }
            /^## \$ volec query callers / { g = $0; sub(/^## \$ volec query callers crate::/, "", g); sub(/ --all$/, "", g); next }
            NF >= 3 && $2 == "call" && ($3 in in_asm) && !($3 in cut) { print $3 "\t" g }' \
        | sort -u >"$WORK/up-level"
    cat "$WORK/up-level" >>"$WORK/up-edges"
    sort -u "$WORK/up-seen" -o "$WORK/up-seen"
    cut -f1 "$WORK/up-level" | sort -u | comm -23 - "$WORK/up-seen" >"$WORK/up-new"
done
awk -F'\t' '{ edge[$1] = edge[$1] " " $2 }
    END {
        q[1] = "back::objfile::assemble_bytes"; seen[q[1]] = 1; h = 1; t = 1
        while (h <= t) {
            g = q[h++]; print g
            m = split(edge[g], c, " ")
            for (i = 1; i <= m; i++) if (!(c[i] in seen)) { seen[c[i]] = 1; q[++t] = c[i] }
        }
    }' "$WORK/up-edges" | sort -u >"$WORK/asm-stream"
awk -F'\t' -v S="$WORK/asm-stream" -v exits="$ASM_EXITS" '
    BEGIN {
        while ((getline f < S) > 0) on[f] = 1
        n = split(exits, e, " "); for (i = 1; i <= n; i++) delete on[e[i]]
    }
    ($2 in on)' "$WORK/asm-touch" >"$WORK/asm-reads"
printf '%s\n' "$ASM_READS" | cut -f1,2 | sort -u >"$WORK/asm-reads-allowed"
newar=$(comm -23 "$WORK/asm-reads" "$WORK/asm-reads-allowed" | tr '\t' ' ')
printf '%s\n' "$newar" | while read -r s f; do
    [ -n "$s" ] && echo "FAIL $s: -O0's main thread writes it while the assembler thread reads it in $f; try: $COMPILER query refs crate::$s --in $f"
done
# (T8) Every static task code touches, against READ.
awk -F'\t' -v reached="$WORK/reached" '
    BEGIN { while ((getline f < reached) > 0) in_task[f] = 1 }
    /^## \$ volec query refs / { s = $0; sub(/^## \$ volec query refs crate::/, "", s); sub(/ --all$/, "", s); next }
    NF >= 4 && $1 ~ /^[0-9]+:[0-9]+$/ { if ($2 != "use" && $2 != "def" && $2 != "init" && ($3 in in_task)) print s }' "$WORK/refs" \
    | sort -u >"$WORK/touched"
printf '%s\n' "$READ" | cut -f1 | sort -u >"$WORK/read-allowed"
newr=$(comm -23 "$WORK/touched" "$WORK/read-allowed")
for s in $newr; do
    echo "FAIL $s: a task reads it, and the code cache does not know how it covers it (tests/threads_writes.sh READ); try: $COMPILER query refs crate::$s"
done
echo "threads-writes: $(wc -l <"$WORK/written" | tr -d ' ') statics written by tasks, $(wc -l <"$WORK/join-written" | tr -d ' ') by the join and used by tasks, $(wc -l <"$WORK/asm-shared" | tr -d ' ') shared by -O0's assembler thread; $(printf '%s\n%s\n%s\n%s\n' "$new" "$newj" "$newa" "$newar" | grep -c .) not known to be race-free; $(wc -l <"$WORK/touched" | tr -d ' ') touched, $(echo "$newr" | grep -c .) the code cache does not cover"
[ -z "$new" ] && [ -z "$newj" ] && [ -z "$newa" ] && [ -z "$newar" ] && [ -z "$newr" ]
