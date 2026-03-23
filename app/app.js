const express = require('express');
const axios = require('axios');
const dns = require('dns');

// Force IPv4 to avoid IPv6 connectivity issues in containerized environments
dns.setDefaultResultOrder('ipv4first');

const app = express();
const PORT = 8080;

// Application State
let priceHistory = [];
let isFetching = false;

/**
 * Retrieves the current Bitcoin price from CoinGecko API.
 * Executed every 1 minute.
 */
async function fetchBitcoinPrice() {
    if (isFetching) {
        console.warn(`[${new Date().toISOString()}] WARN: Skipping fetch - previous still in progress`);
        return; // Prevent overlapping requests
    }

    isFetching = true;
    try {
        const url = 'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd';
        const res = await axios.get(url, {timeout: 8000});
        const price = res?.data?.bitcoin?.usd;

        if (price == null) {
            throw new Error('Invalid API response');
        }
            
        console.log(`[${new Date().toISOString()}] FETCH: Current BTC Price: $${price}`);

        priceHistory.push(price);

        // Keep only the last 10 minutes of data (Sliding Window)
        if (priceHistory.length > 10) {
            priceHistory.shift();
        }
    } catch (error) {
        console.error(`[${new Date().toISOString()}] ERROR: Failed to fetch price: ${error.message}`);
    }
    finally {
        isFetching = false;
    }
}

/**
 * Calculates the average of the current price history.
 * @returns {number} The average price, or 0 if priceHistory is empty.
 */
function calculateAverage() {
    const count = priceHistory.length;
    if (count === 0) return 0;

    const sum = priceHistory.reduce((a, b) => a + b, 0);
    return sum / count;
}

/**
 * Handles the display logic for the 10-minute average.
 * Executed every 10 minutes by setInterval.
 */
function logAverageReport() {
    const count = priceHistory.length;
    const avg = calculateAverage();

    if (count === 0) {
        console.log(`[${new Date().toISOString()}] AVG: No data available yet.`);
        return;
    }

    console.log(`[${new Date().toISOString()}] >>> AVG: 10-Minute Average: $${avg.toFixed(2)} (Based on ${count} samples)`);
}


// --- Scheduling ---
fetchBitcoinPrice(); // Immediate initial fetch
setInterval(fetchBitcoinPrice, 60 * 1000); // Every 1 min
setInterval(logAverageReport, 10 * 60 * 1000); // Every 10 min

// --- Routes ---
app.get('/', (req, res) => {
  res.send('<h1>Service A is Running!</h1><p>Check the pod logs to see real-time BTC prices and average.</p>');
});

// Endpoints for the Kubernetes Probes
// Liveness Probe: Checks if the process is alive
app.get('/healthz', (req, res) => {
    res.status(200).send('Alive')
});

// Readiness Probe: Checks if the app is ready to serve traffic
app.get('/ready', (req, res) => {
    // App is ready only after the first successful price fetch
    if (priceHistory.length > 0) {
        return res.status(200).send('Ready');
    }
    
    res.status(503).send('Not Ready');
});

app.listen(PORT, () => {
    console.log(`[${new Date().toISOString()}] SERVER: Service A listening on port ${PORT}`);
});