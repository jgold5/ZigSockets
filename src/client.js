const WebSocket = require('ws');

const socket = new WebSocket('ws://127.0.0.1:8000');

socket.on('open', function() {
    console.log('WebSocket connection established');
    socket.send('Hello, Server!');
});
