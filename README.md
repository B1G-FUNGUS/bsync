# Description

An rsync wrapper program, with two main goals:

1. The ability to batch sync files/folders with different paths on different
machines (rsync can somewhat do this on its own, but not to the extent this 
script allows)

2. The ability to restrict deletions to files that were deleted after a sync,
while still copying over files that were added after a sync

# TODO

- Add a license?

- Add a "Usage" section to the README

- Fix known escaping issues

 - Technically the rsync related ones can be fixed by doing something like:

 ```bash
cd "$alias_l"
find "$alias_l" ! -newer "$last_l" -print0 | 
  sed -z 's/\n/\\n' | tr '\0' '\n' | tac > "$filter-l"
# do the same thing for the remote host

diff "$filter-l" "$filter-r" > "$filter-d"
grep '^<' "$filter-d" | cut 3- | tr '\n' '\0' | sed -z 's/\\n/\n' |
  xargs -0 $remove -r
# same for remote
```

Why not implement this solution? Basically rsync has to retread ground and check
old files, which in the current solution does not happen. Additionally, this
is more of a prove of concept, and ideally I would like to be able to implement 
this syncing based off of a file's date in rsync directly, but who knows, maybe
it's best that this is just a script.

# Known Issues

- If you remove a folder from the config, add new files, sync two machines who
have that folder, and then add that folder back into the config, all of the new
files will be considered old, and thus deleted, on the next sync. This is
simply a fact of how this script works, and will not be fixed. In order to
fix this problem, you would need to store information about each folder, and
at that point it would be better to instead make a more reliable and capable
Python script.

## special characters in pathnames

In general I recommend avoiding using this program with files that may contain
unusual characters. Here are some known characters that will break this program:

- If $TMPDIR contains a single quote, then it will break the program as ssh
won't be able to parse it

- If ANY files (including child files in a parent files) contain '\*' '?' or '['
then rsync will interpret them as pattern matching characters. Thus, a simple
grep command excludes such files from the sync.

- If a file contains the newline character, it will be treated as two separate
files in the filter. This *can* cause accidental deletions, but should be rare,
so there currently is no check for them
