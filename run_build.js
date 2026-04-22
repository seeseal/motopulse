const { execSync } = require('child_process');
const fs = require('fs');
const projectDir = 'C:\\Users\\cecil\\motopulse';
const log = projectDir + '\\build_v140_log.txt';

// Let child process fully inherit the parent environment (no explicit env override)
const opts = {
  cwd: projectDir,
  shell: true,
  encoding: 'utf8',
  timeout: 600000,
  maxBuffer: 20 * 1024 * 1024,
};

function run(label, cmd) {
  fs.appendFileSync(log, '\n=== ' + label + ' ===\n');
  console.log('Running: ' + label);
  try {
    const out = execSync(cmd, opts);
    fs.appendFileSync(log, out);
    console.log(out.slice(-500));
    return true;
  } catch (e) {
    const msg = (e.stdout || '') + '\n' + (e.stderr || '') + '\nERROR: ' + e.message;
    fs.appendFileSync(log, msg);
    console.error(msg.slice(-500));
    return false;
  }
}

fs.writeFileSync(log, '=== v1.4.0 Build started: ' + new Date().toISOString() + ' ===\n');

const pubOk = run('flutter pub get', 'C:\\flutter\\bin\\flutter.bat pub get');
const bldOk = pubOk && run('flutter build apk', 'C:\\flutter\\bin\\flutter.bat build apk --release --target-platform android-arm64');

if (bldOk) {
  const src  = projectDir + '\\build\\app\\outputs\\flutter-apk\\app-release.apk';
  const dest = projectDir + '\\build\\app\\outputs\\flutter-apk\\MotoPulse-v1.4.0.apk';
  try {
    fs.copyFileSync(src, dest);
    fs.appendFileSync(log, '\nAPK copied -> MotoPulse-v1.4.0.apk\n');
    console.log('APK ready: MotoPulse-v1.4.0.apk');
  } catch (e) {
    fs.appendFileSync(log, '\nERROR copying APK: ' + e.message + '\n');
  }
}

fs.appendFileSync(log, '\n=== Done: ' + new Date().toISOString() + ' ===\n');
console.log('Finished. Check build_v140_log.txt');
