const WebSocket = require('ws');

const socket = new WebSocket('ws://127.0.0.1:8000');


function sleepSync(ms) {
    const start = Date.now();
    while (Date.now() - start < ms) {}
}


socket.on('open', function() {
    console.log('WebSocket connection established');
    sleepSync(1500);
    socket.send('hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh');
    sleepSync(2500);
    socket.send('howdy');
    sleepSync(1000);
    socket.send('wazz good g');
});

socket.onerror = (event) => {
    console.error("WebSocket error:", event);
};

setTimeout(() => {
    socket.close();
    console.log("WebSocket closed");
}, 5000);


function sleepSync(ms) {
    const start = Date.now();
    while (Date.now() - start < ms) {}
}
