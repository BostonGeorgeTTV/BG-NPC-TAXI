const meter = document.getElementById('taxi-meter');
const fareEl = document.getElementById('fare');
const kmEl = document.getElementById('km');

window.addEventListener('message', (event) => {
  const data = event.data || {};

  if (data.action === 'show') {
    meter.style.display = 'block';
    return;
  }

  if (data.action === 'hide') {
    meter.style.display = 'none';
    return;
  }

  if (data.action === 'update') {
    fareEl.textContent = `$${Number(data.fare || 0)}`;
    kmEl.textContent = `${data.km || '0.00'}`;
  }
});
