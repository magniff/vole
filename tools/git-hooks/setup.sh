#!/bin/sh
# Sets up a clone for vole's commit hook and merge driver, once (the
# repository's config, shared by all its worktrees):
#
#   core.hooksPath       tools/git-hooks: the commit-time checks (pre-commit)
#   merge.stdsrc.driver  (0.25.3) compiler/src/front/stdsrc.vl is made
#                        again from the merged compiler/std, never merged as
#                        text (tools/git-hooks/merge-stdsrc; .gitattributes)
#
# usage: tools/git-hooks/setup.sh
set -eu
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath tools/git-hooks
git config merge.stdsrc.name "compiler/src/front/stdsrc.vl, made from the merged compiler/std"
git config merge.stdsrc.driver 'sh tools/git-hooks/merge-stdsrc %O %A %B %P'
echo "setup: core.hooksPath and merge.stdsrc set in $(git rev-parse --git-common-dir)/config"
