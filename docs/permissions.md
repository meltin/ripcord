# Permissions

Pasting from Clipboard History or Search Snippets presses ⌘V for you, which needs Ripcord to
be allowed under System Settings › Privacy & Security › Accessibility; Ripcord asks once per
launch, on the first paste. Until then, Return only copies the item and beeps. Snippet keywords
need the same permission to expand.

macOS ties the permission to how the app is signed. A build signed ad hoc, as one made without
the certificate below is, counts as a new app each time, so after an update remove Ripcord from
that list and add it again, or run `tccutil reset Accessibility io.github.meltin.ripcord`. To
build from source and keep the permission across rebuilds, create a signing certificate once:

```sh
scripts/create-signing-certificate.sh
```

It adds a self-signed certificate to your login keychain and asks for your password once, to trust
it for code signing. `scripts/build-app.sh` signs with it from then on. Once after creating it,
remove Ripcord from the Accessibility list (or run the `tccutil reset` command above) and grant it
to the next build; later builds keep it.

Releases after 0.1.0 are signed with the project's own certificate, the same one each time, so an
update keeps the permission. Moving from 0.1.0, which was signed ad hoc, grant it once more.

System Actions use Accessibility for the music and volume keys too, as Window Management does to
move windows. Empty Trash, Toggle System Appearance and Log Out, Restart and Shut Down ask macOS
to let Ripcord control Finder, System Events and the login window; allow it in the prompt, or
later under System Settings › Privacy & Security › Automation.

Lid Awake sets `pmset -a disablesleep 1`, which takes root, so Settings › Lid Awake asks once for
an administrator password to add a sudoers rule (`/etc/sudoers.d/ripcord-lid-awake`) allowing
exactly `pmset -a disablesleep 0` and `1`; Remove… there takes it out.
