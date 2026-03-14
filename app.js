const express = require('express');
const helmet  = require('helmet');
const morgan  = require('morgan');
const os      = require('os');

const app  = express();
const PORT = process.env.PORT || 3000;

// ── Security middleware ─────────────────
app.use(helmet());
app.use(express.json());
app.use(morgan('combined'));

// ── Health check ───────────────────────
app.get('/health', (req, res) => {
  res.status(200).json({
    status:   'healthy',
    uptime:   process.uptime(),
    hostname: os.hostname(),
    time:     new Date().toISOString()
  });
});

// ── Readiness probe ────────────────────
app.get('/ready', (req, res) => {
  res.status(200).json({ status: 'ready' });
});

// ── Metrics endpoint (Prometheus) ──────
app.get('/metrics', (req, res) => {
  const mem = process.memoryUsage();
  res.set('Content-Type', 'text/plain');
  res.send(`
# HELP nodejs_heap_used_bytes Heap used
# TYPE nodejs_heap_used_bytes gauge
nodejs_heap_used_bytes ${mem.heapUsed}

# HELP nodejs_heap_total_bytes Heap total
# TYPE nodejs_heap_total_bytes gauge
nodejs_heap_total_bytes ${mem.heapTotal}

# HELP nodejs_rss_bytes RSS memory
# TYPE nodejs_rss_bytes gauge
nodejs_rss_bytes ${mem.rss}

# HELP nodejs_uptime_seconds Process uptime
# TYPE nodejs_uptime_seconds counter
nodejs_uptime_seconds ${process.uptime()}
  `.trim());
});

// ── Main route ─────────────────────────
app.get('/', (req, res) => {
  res.status(200).json({
    app:         'CloudShield DevSecOps',
    version:     process.env.APP_VERSION || '1.0.0',
    environment: process.env.NODE_ENV    || 'development',
    hostname:    os.hostname(),
    time:        new Date().toISOString()
  });
});

// ── API routes ─────────────────────────
app.get('/api/info', (req, res) => {
  res.status(200).json({
    node:     process.version,
    platform: process.platform,
    arch:     process.arch,
    env:      process.env.NODE_ENV || 'development'
  });
});

// ── 404 handler ────────────────────────
app.use((req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

// ── Error handler ──────────────────────
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Internal server error' });
});

// ── Start server ───────────────────────
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});

module.exports = app;
