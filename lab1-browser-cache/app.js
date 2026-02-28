// Browser Cache Lab - app.js
console.log('App loaded at:', new Date().toISOString());

document.getElementById('load-time').textContent = new Date().toLocaleTimeString();
setInterval(() => {
    document.getElementById('current-time').textContent = new Date().toLocaleTimeString();
}, 1000);
