import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const destination = path.resolve(process.argv[2] || path.join(root, 'build/launcher-project'));
if (fs.existsSync(path.join(destination, 'project.godot'))) {
  throw new Error('Use an empty destination for the launcher project.');
}
fs.mkdirSync(path.join(destination, 'bootstrap'), { recursive: true });
let project = fs.readFileSync(path.join(root, 'project.godot'), 'utf8')
  .replace(/^run\/main_scene=.*$/m, 'run/main_scene="res://bootstrap/launcher.tscn"')
  .replace(/^config\/patch_id=.*$/m, 'config/patch_id=0')
  .replace(/\[autoload\]\s*[\s\S]*?(?=\[|$)/, '');
fs.writeFileSync(path.join(destination, 'project.godot'), project);
fs.copyFileSync(path.join(root, 'icon.svg'), path.join(destination, 'icon.svg'));
fs.copyFileSync(path.join(root, 'tools/release/launcher.gd.txt'), path.join(destination, 'bootstrap/launcher.gd'));
fs.copyFileSync(path.join(root, 'update/pck_updater.gd'), path.join(destination, 'bootstrap/pck_updater.gd'));
fs.copyFileSync(path.join(root, 'tools/release/launcher_export_presets.cfg'), path.join(destination, 'export_presets.cfg'));
fs.writeFileSync(path.join(destination, 'bootstrap/launcher.tscn'), `[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://bootstrap/launcher.gd" id="1"]
[node name="Launcher" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")
`);
console.log(destination);
