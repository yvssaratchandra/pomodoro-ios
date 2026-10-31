'use strict';
window.addEventListener('message', event => {
  if (event.origin !== location.origin || event.source !== parent || event.data?.type !== 'pomodoro-preview') return;
  const config = event.data;
  if (!screens.some(([name]) => name === config.screen) || !['ready','running','breakReady','breakRunning','dim','empty'].includes(config.phase)) return;
  clearTimeout(dimTimeout); clearTimeout(undoTimeout);
  data = initialData();
  state = {...state, screen:config.screen, phase:config.phase, theme:config.theme === 'dark' ? 'dark' : 'light', large:!!config.large, project:'work', projectDetail:null, settingsPage:null, inactive:false,showOnHold:false,showCompleted:false,projectMenu:false, thoughtFilter:'All', thoughtProject:'all',query:'',range:'Day',periodOffset:0,statsProject:'all',editor:null,dialog:null,undo:null};
  document.documentElement.style.setProperty('--preview-width', `${[360,393,412].includes(config.width) ? config.width : 412}px`);
  render();
  announce('');
});
