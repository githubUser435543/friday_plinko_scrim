(() => {
  const clock = document.querySelector('#mission-clock');
  let seconds = (5 * 24 * 60 * 60) + (14 * 60 * 60) + 61;
  if (clock) setInterval(() => {
    seconds += 1;
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const mins = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;
    clock.textContent = `T+ ${days}:${String(hours).padStart(2,'0')}:${String(mins).padStart(2,'0')}:${String(secs).padStart(2,'0')}`;
  }, 1000);

  document.querySelectorAll('[data-panel]').forEach(button => button.addEventListener('click', () => {
    document.querySelectorAll('[data-panel]').forEach(item => item.classList.remove('selected'));
    document.querySelectorAll('.panel').forEach(panel => panel.classList.remove('active-panel'));
    button.classList.add('selected');
    document.querySelector(`#${button.dataset.panel}`)?.classList.add('active-panel');
  }));
})();
