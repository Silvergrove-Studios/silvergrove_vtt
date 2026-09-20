# Debug signing key

`debug.keystore` (PKCS12, password `android`, alias `androiddebugkey`) signs
the Android builds CI produces. It is a **debug** key: it grants nothing and
exists only so that every build is signed the same way — Android will not
update an installed app whose signature changed ("App not installed").
Keep it; a store release will need a real key kept out of the repository.
