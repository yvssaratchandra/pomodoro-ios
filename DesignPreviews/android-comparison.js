'use strict';
const controls = Object.fromEntries(['screen','phase','theme','width','large'].map(id => [id, document.getElementById(id)]));
function updateFrames() {
  const payload = {type:'pomodoro-preview', screen:controls.screen.value, phase:controls.phase.value, theme:controls.theme.value, width:Number(controls.width.value), large:controls.large.checked};
  document.querySelectorAll('iframe').forEach(frame => frame.contentWindow.postMessage(payload, location.origin));
}
Object.values(controls).forEach(control => control.addEventListener('change', () => {
  if (control === controls.phase) controls.screen.value='focus';
  updateFrames();
}));
document.getElementById('reset').addEventListener('click', updateFrames);
document.querySelectorAll('iframe').forEach(frame => frame.addEventListener('load', updateFrames));
