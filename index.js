const { Worker } = require('worker_threads');

const numThreads = 10;
 
for (let i = 0; i < numThreads; i++) {
    const worker = new Worker('./bruteforce.js'); 
 
    worker.on('message', (msg) => {
        if (msg === 'done') {
            worker.postMessage('start');  
        }
    });
}
