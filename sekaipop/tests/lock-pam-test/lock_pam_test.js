// Source checks for the lockscreen's PAM choice: the distro's "login" everywhere, except a
// Nix-built Quickshell on a distro that isn't NixOS (install-deps-debian.sh), which uses the
// bundled pam/lock-password because Nix's libpam can't load the distro's own modules
// (pam_ecryptfs on Mint) and would fail every password with a PAM error.
// Run:  node tests/lock-pam-test/lock_pam_test.js
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const { execFileSync } = require("child_process");

const top = path.join(__dirname, "..", "..");
const read = rel => fs.readFileSync(path.join(top, rel), "utf8");
const ctx = read("modules/sekai/lock/LockContext.qml");
const conf = read("modules/sekai/lock/pam/lock-password");

let n = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); n++; };

// ---- the bundled config: only pam_unix, nothing a distro may lack ----
const lines = conf.split("\n").map(l => l.trim()).filter(l => l && !l.startsWith("#"));
ok(lines.length === 1 && /^auth\s+required\s+pam_unix\.so$/.test(lines[0]), "lock-password is just auth pam_unix");

// ---- the password PamContext switches on nixOnDistro, and only there ----
ok(/property bool nixOnDistro: false/.test(ctx), "nixOnDistro starts false (the distro's login)");
ok(/property string pamService: "login"/.test(ctx), "pamService is still login");
const pamBlock = /PamContext \{\s*id: pam\n([\s\S]*?)\n    \}/.exec(ctx);
ok(pamBlock, "password PamContext found");
ok(/configDirectory: root\.nixOnDistro \? Quickshell\.shellDir \+ "\/modules\/sekai\/lock\/pam" : "\/etc\/pam\.d"/.test(pamBlock[1]),
   "configDirectory: bundled folder only on Nix-on-distro");
ok(/config: root\.nixOnDistro \? "lock-password" : root\.pamService/.test(pamBlock[1]),
   "config: lock-password only on Nix-on-distro");

// ---- the detection command: NixOS exits quietly; otherwise "nix" only for a /nix/store parent ----
const cm = /id: nixCheck[\s\S]*?command: \["sh", "-c", "((?:[^"\\]|\\.)*)"\]/.exec(ctx);
ok(cm, "nixCheck command found");
const script = JSON.parse('"' + cm[1] + '"');
ok(/\[ -e \/etc\/NIXOS \] && exit 0;/.test(script), "NixOS keeps its own /etc/pam.d");
// The parent of sh here is node: never in /nix/store on a distro install... unless it is.
const nodeExe = fs.readlinkSync("/proc/self/exe");
const out = execFileSync("sh", ["-c", script], { encoding: "utf8" }).trim();
if (!fs.existsSync("/etc/NIXOS"))
    ok(out === (nodeExe.startsWith("/nix/store/") ? "nix" : ""), "detection follows the parent's executable");

console.log("lock-pam-test: " + n + " checks passed");
