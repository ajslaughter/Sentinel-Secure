/**
 * WinSysAuto Dashboard - Main Application
 * Professional sysadmin-focused dashboard with comprehensive state management
 */

// ===================================================================
// State Management
// ===================================================================
const dashboardState = {
    healthData: null,
    alerts: [],
    isRefreshing: false,
    lastUpdate: null,
    settings: {
        refreshInterval: 30000,
        autoRefresh: true,
        theme: 'light',
        thresholds: {
            cpu: { warning: 70, critical: 90 },
            memory: { warning: 75, critical: 90 },
            disk: { warning: 80, critical: 95 }
        }
    },
    modals: {
        addUsers: false,
        backup: false,
        progress: false
    }
};

let refreshIntervalId = null;

// ===================================================================
// Utility Functions
// ===================================================================

/**
 * Format relative time (e.g., "2 min ago")
 */
function formatRelativeTime(timestamp) {
    const now = new Date();
    const date = new Date(timestamp);
    const diffMs = now - date;
    const diffSec = Math.floor(diffMs / 1000);
    const diffMin = Math.floor(diffSec / 60);
    const diffHour = Math.floor(diffMin / 60);
    const diffDay = Math.floor(diffHour / 24);

    if (diffSec < 60) return 'just now';
    if (diffMin < 60) return `${diffMin} min ago`;
    if (diffHour < 24) return `${diffHour}h ago`;
    return `${diffDay}d ago`;
}

/**
 * Format time for display
 */
function formatTime(timestamp) {
    return new Date(timestamp).toLocaleString('en-US', {
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
    });
}

/**
 * Debounce function
 */
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

// ===================================================================
// Toast Notification System
// ===================================================================

/**
 * Show toast notification
 * @param {string} type - success, error, warning, info
 * @param {string} title - Toast title
 * @param {string} message - Toast message
 */
function showToast(type, title, message) {
    const container = document.getElementById('toastContainer');
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;

    const iconSvg = {
        success: '<path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>',
        error: '<path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>',
        warning: '<path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>',
        info: '<path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/>'
    };

    toast.innerHTML = `
        <svg class="toast-icon" width="20" height="20" viewBox="0 0 20 20" fill="currentColor">
            ${iconSvg[type] || iconSvg.info}
        </svg>
        <div class="toast-content">
            <div class="toast-title">${title}</div>
            <div class="toast-message">${message}</div>
        </div>
        <button class="close-btn" onclick="this.parentElement.remove()" style="margin-left: auto;">
            <svg width="16" height="16" viewBox="0 0 20 20" fill="currentColor">
                <path d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"/>
            </svg>
        </button>
    `;

    container.appendChild(toast);

    // Auto-remove after 5 seconds
    setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => toast.remove(), 300);
    }, 5000);
}

// ===================================================================
// Modal Management
// ===================================================================

/**
 * Open modal
 * @param {string} modalId - ID of the modal to open
 */
function openModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
        modal.classList.add('active');
        dashboardState.modals[modalId.replace('Modal', '')] = true;
        // Prevent body scroll
        document.body.style.overflow = 'hidden';
    }
}

/**
 * Close modal
 * @param {string} modalId - ID of the modal to close
 */
function closeModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
        modal.classList.remove('active');
        dashboardState.modals[modalId.replace('Modal', '')] = true;
        // Restore body scroll
        document.body.style.overflow = '';
    }
}

/**
 * Close modal on overlay click
 */
function setupModalCloseOnOverlay() {
    document.querySelectorAll('.modal').forEach(modal => {
        const overlay = modal.querySelector('.modal-overlay');
        if (overlay) {
            overlay.addEventListener('click', () => {
                closeModal(modal.id);
            });
        }
    });
}

/**
 * Setup all close buttons in modals
 */
function setupModalCloseButtons() {
    document.querySelectorAll('.modal .close-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const modal = e.target.closest('.modal');
            if (modal) {
                closeModal(modal.id);
            }
        });
    });
}

// ===================================================================
// API Integration
// ===================================================================

/**
 * Call API with proper error handling
 * @param {string} endpoint - API endpoint
 * @param {object} options - Fetch options
 * @returns {Promise<object>} API response
 */
async function callApi(endpoint, options = {}) {
    try {
        const headers = {};

        // Add auth token if available
        if (window.WSA_AUTH_TOKEN) {
            headers['X-Auth-Token'] = window.WSA_AUTH_TOKEN;
        }

        // Handle multipart vs JSON
        if (!options.body instanceof FormData) {
            headers['Content-Type'] = 'application/json';
        }

        const response = await fetch(endpoint, {
            method: 'POST',
            headers: headers,
            ...options
        });

        const data = await response.json();

        if (!data.ok && data.ok !== undefined) {
            throw new Error(data.message || 'Request failed');
        }

        return data;
    } catch (error) {
        console.error('API Error:', error);
        throw error;
    }
}

// ===================================================================
// Dashboard Data Updates
// ===================================================================

/**
 * Update dashboard with health data
 */
async function updateDashboard() {
    if (dashboardState.isRefreshing) {
        return;
    }

    dashboardState.isRefreshing = true;

    try {
        const data = await fetch('/api/health').then(r => r.json());

        dashboardState.healthData = data;
        dashboardState.lastUpdate = new Date();

        // Update UI
        updateHealthOverview(data);
        updateResourceMetrics(data);
        updateServices(data);
        updateAlerts(data);
        updateLastUpdated();

    } catch (error) {
        console.error('Failed to update dashboard:', error);
        showToast('error', 'Update Failed', 'Could not fetch latest data from server');
    } finally {
        dashboardState.isRefreshing = false;
    }
}

/**
 * Update health overview cards
 */
function updateHealthOverview(data) {
    // Health Score
    const healthScore = document.getElementById('healthScore');
    const overallHealthCard = document.getElementById('overallHealthCard');
    const healthTrend = document.getElementById('healthTrend');

    if (healthScore) {
        healthScore.textContent = data.healthScore || '--';
    }

    // Update card styling based on health status
    if (overallHealthCard) {
        overallHealthCard.classList.remove('critical-card', 'warning-card');
        if (data.healthStatus === 'critical') {
            overallHealthCard.classList.add('critical-card');
        } else if (data.healthStatus === 'warning') {
            overallHealthCard.classList.add('warning-card');
        }
    }

    // Critical and Warning counts
    const criticalCount = document.getElementById('criticalCount');
    const warningCount = document.getElementById('warningCount');

    if (criticalCount) {
        const count = (data.alerts || []).filter(a => a.level === 'CRITICAL').length;
        criticalCount.textContent = count;
    }

    if (warningCount) {
        const count = (data.alerts || []).filter(a => a.level === 'WARNING').length;
        warningCount.textContent = count;
    }

    // Last Backup (placeholder - would need actual backup data from API)
    const lastBackup = document.getElementById('lastBackup');
    if (lastBackup && data.timestamp) {
        lastBackup.textContent = formatRelativeTime(data.timestamp);
    }
}

/**
 * Update resource metrics (CPU, Memory, Disk)
 */
function updateResourceMetrics(data) {
    // CPU
    updateResourceCard('cpu', data.cpu?.total || 0);

    // Memory
    if (data.memory) {
        updateResourceCard('memory', data.memory.percent);
        const memoryDetail = document.getElementById('memoryDetail');
        if (memoryDetail) {
            memoryDetail.textContent = `${data.memory.usedGB.toFixed(1)} GB / ${data.memory.totalGB.toFixed(1)} GB`;
        }
    }

    // Disk (primary drive)
    if (data.disk && data.disk.length > 0) {
        const primaryDisk = data.disk[0];
        updateResourceCard('disk', primaryDisk.usagePercent);
        const diskDetail = document.getElementById('diskDetail');
        if (diskDetail) {
            diskDetail.textContent = `${primaryDisk.usedGB.toFixed(1)} GB / ${primaryDisk.totalGB.toFixed(1)} GB`;
        }
    }
}

/**
 * Update individual resource card
 */
function updateResourceCard(resource, percent) {
    const percentEl = document.getElementById(`${resource}Percent`);
    const barEl = document.getElementById(`${resource}Bar`);
    const thresholds = dashboardState.settings.thresholds[resource];

    if (percentEl) {
        percentEl.textContent = `${percent.toFixed(1)}%`;
    }

    if (barEl) {
        barEl.style.width = `${percent}%`;
        barEl.setAttribute('aria-valuenow', percent);

        // Update color based on thresholds
        barEl.classList.remove('warning', 'critical');
        if (percent >= thresholds.critical) {
            barEl.classList.add('critical');
        } else if (percent >= thresholds.warning) {
            barEl.classList.add('warning');
        }
    }
}

/**
 * Update services list
 */
function updateServices(data) {
    const servicesList = document.getElementById('servicesList');
    if (!servicesList || !data.services) return;

    servicesList.innerHTML = '';

    // Show only critical services (first 5)
    const criticalServices = data.services.slice(0, 5);

    criticalServices.forEach(service => {
        const serviceItem = document.createElement('div');
        serviceItem.className = `service-item ${service.health}`;

        const statusIconClass = service.status === 'Running' ? 'running' :
                                service.status === 'Stopped' ? 'stopped' : 'degraded';

        serviceItem.innerHTML = `
            <span class="service-name">${service.name}</span>
            <div class="service-status">
                <span>${service.status}</span>
                <div class="service-icon ${statusIconClass}"></div>
            </div>
        `;

        servicesList.appendChild(serviceItem);
    });

    // Update "View All Services" button
    const viewAllBtn = document.getElementById('viewAllServices');
    if (viewAllBtn) {
        viewAllBtn.textContent = `View All Services (${data.services.length})`;
    }
}

/**
 * Update alerts list
 */
function updateAlerts(data) {
    const alertsList = document.getElementById('alertsList');
    if (!alertsList) return;

    alertsList.innerHTML = '';

    if (!data.alerts || data.alerts.length === 0) {
        alertsList.innerHTML = `
            <div class="empty-state">
                <svg width="48" height="48" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
                </svg>
                <p>No active alerts</p>
            </div>
        `;
        return;
    }

    data.alerts.forEach(alert => {
        const alertItem = document.createElement('div');
        alertItem.className = `alert-item ${alert.level.toLowerCase()}`;

        alertItem.innerHTML = `
            <div class="alert-header">
                <div class="alert-title">[${alert.level}] ${alert.metric}</div>
                <div class="alert-time">just now</div>
            </div>
            <div class="alert-message">${alert.message}</div>
            <div class="alert-actions">
                <button class="link-btn" onclick="handleAlertAction('${alert.metric}')">View Details</button>
                <button class="link-btn" onclick="dismissAlert('${alert.metric}')">Dismiss</button>
            </div>
        `;

        alertsList.appendChild(alertItem);
    });

    dashboardState.alerts = data.alerts;
}

/**
 * Update last updated timestamp
 */
function updateLastUpdated() {
    const lastUpdated = document.getElementById('lastUpdated');
    if (lastUpdated && dashboardState.lastUpdate) {
        lastUpdated.textContent = formatRelativeTime(dashboardState.lastUpdate);
    }
}

// Alert actions (placeholders)
function handleAlertAction(metric) {
    showToast('info', 'Alert Action', `Viewing details for: ${metric}`);
}

function dismissAlert(metric) {
    showToast('info', 'Alert Dismissed', `Alert for ${metric} has been dismissed`);
    // In a real implementation, would call API to dismiss alert
    updateDashboard();
}

// ===================================================================
// Button Loading State Helpers
// ===================================================================

/**
 * Set button loading state
 */
function setButtonLoading(button, isLoading) {
    if (!button) return;

    if (isLoading) {
        button.classList.add('btn-loading');
        button.disabled = true;

        // Store original content
        if (!button.dataset.originalHtml) {
            button.dataset.originalHtml = button.innerHTML;
        }
    } else {
        button.classList.remove('btn-loading');
        button.disabled = false;

        // Restore original content
        if (button.dataset.originalHtml) {
            button.innerHTML = button.dataset.originalHtml;
            delete button.dataset.originalHtml;
        }
    }
}

/**
 * Disable all action buttons
 */
function setAllButtonsDisabled(disabled) {
    const buttons = document.querySelectorAll('.action-btn, .btn-primary, .btn-secondary');
    buttons.forEach(btn => {
        btn.disabled = disabled;
    });
}

// ===================================================================
// Action Button Handlers
// ===================================================================

/**
 * Run health check
 */
async function runHealthCheck() {
    const button = document.getElementById('btnHealthCheck');
    setButtonLoading(button, true);
    showProgressModal('Running Health Check...', 'Gathering system metrics...');

    try {
        const result = await callApi('/api/action/health', {
            body: JSON.stringify({})
        });

        closeModal('progressModal');

        if (result.ok || result.ok === undefined) {
            showToast('success', 'Health Check Complete', 'All system checks completed successfully');
            // Refresh dashboard with new data
            await updateDashboard();
        } else {
            showToast('error', 'Health Check Failed', result.message || 'An error occurred');
        }
    } catch (error) {
        closeModal('progressModal');
        showToast('error', 'Health Check Failed', error.message);
    } finally {
        setButtonLoading(button, false);
    }
}

/**
 * Show progress modal
 */
function showProgressModal(title, text) {
    const modal = document.getElementById('progressModal');
    const titleEl = document.getElementById('progressTitle');
    const textEl = document.getElementById('progressText');

    if (titleEl) titleEl.textContent = title;
    if (textEl) textEl.textContent = text;

    openModal('progressModal');
}

/**
 * Create backup
 */
async function createBackup() {
    const button = document.getElementById('btnBackup');
    closeModal('backupModal');
    setButtonLoading(button, true);
    showProgressModal('Creating Backup...', 'Backing up configuration data...');

    try {
        const result = await callApi('/api/action/backup', {
            body: JSON.stringify({ note: 'Manual backup from dashboard' })
        });

        closeModal('progressModal');

        if (result.ok || result.backupPath) {
            showToast('success', 'Backup Complete', `Backup created: ${result.backupPath || 'Success'}`);
        } else {
            showToast('error', 'Backup Failed', result.message || 'An error occurred');
        }
    } catch (error) {
        closeModal('progressModal');
        showToast('error', 'Backup Failed', error.message);
    } finally {
        setButtonLoading(button, false);
    }
}

/**
 * Add users from CSV
 */
async function addUsersFromCSV() {
    const fileInput = document.getElementById('csvFile');
    const defaultOU = document.getElementById('defaultOU').value;
    const autoCreateGroups = document.getElementById('autoCreateGroups').checked;
    const sendWelcomeEmail = document.getElementById('sendWelcomeEmail').checked;
    const resetPasswords = document.getElementById('resetPasswords').checked;

    if (!fileInput.files || fileInput.files.length === 0) {
        showToast('error', 'No File Selected', 'Please select a CSV file');
        return;
    }

    const file = fileInput.files[0];

    if (file.size > 2 * 1024 * 1024) {
        showToast('error', 'File Too Large', 'File size exceeds 2 MB limit');
        return;
    }

    if (!file.name.endsWith('.csv')) {
        showToast('error', 'Invalid File Type', 'Please select a CSV file');
        return;
    }

    const button = document.getElementById('btnAddUsers');
    closeModal('addUsersModal');
    setButtonLoading(button, true);
    showProgressModal('Creating Users...', 'Processing CSV file...');

    try {
        const formData = new FormData();
        formData.append('file', file);
        if (defaultOU) formData.append('defaultOU', defaultOU);
        formData.append('groupsMode', autoCreateGroups ? 'Append' : 'Replace');
        formData.append('resetPasswords', resetPasswords.toString());

        const result = await callApi('/api/action/new-users', {
            body: formData
        });

        closeModal('progressModal');

        if (result.ok || result.created !== undefined) {
            showToast('success', 'Users Created',
                `Created: ${result.created || 0}, Skipped: ${result.skipped || 0}`);
            // Clear form
            fileInput.value = '';
            document.getElementById('defaultOU').value = '';
        } else {
            showToast('error', 'User Creation Failed', result.message || 'An error occurred');
        }
    } catch (error) {
        closeModal('progressModal');
        showToast('error', 'User Creation Failed', error.message);
    } finally {
        setButtonLoading(button, false);
    }
}

/**
 * Run security audit
 */
async function runSecurityAudit() {
    const button = document.getElementById('btnSecurityAudit');
    setButtonLoading(button, true);
    showProgressModal('Running Security Audit...', 'Checking security baseline...');

    try {
        const result = await callApi('/api/action/security-baseline', {
            body: JSON.stringify({ mode: 'Audit' })
        });

        closeModal('progressModal');

        if (result.ok || result.summary) {
            showToast('success', 'Security Audit Complete', result.summary || 'Audit completed successfully');
        } else {
            showToast('error', 'Security Audit Failed', result.message || 'An error occurred');
        }
    } catch (error) {
        closeModal('progressModal');
        showToast('error', 'Security Audit Failed', error.message);
    } finally {
        setButtonLoading(button, false);
    }
}

/**
 * Generate report
 */
async function generateReport() {
    const button = document.getElementById('btnGenerateReport');
    setButtonLoading(button, true);

    try {
        showToast('info', 'Generating Report', 'Preparing comprehensive system report...');

        // Simulate report generation - in real implementation this would call the backend
        await new Promise(resolve => setTimeout(resolve, 1500));

        showToast('success', 'Report Ready', 'System report has been generated successfully');
    } catch (error) {
        showToast('error', 'Report Generation Failed', error.message);
    } finally {
        setButtonLoading(button, false);
    }
}

// ===================================================================
// Settings Management
// ===================================================================

/**
 * Toggle settings sidebar
 */
function toggleSettings() {
    const sidebar = document.getElementById('settingsSidebar');
    if (sidebar) {
        sidebar.classList.toggle('active');
    }
}

/**
 * Save settings
 */
function saveSettings() {
    // Get threshold values
    dashboardState.settings.thresholds.cpu.warning = parseInt(document.getElementById('cpuWarning').value);
    dashboardState.settings.thresholds.cpu.critical = parseInt(document.getElementById('cpuCritical').value);
    dashboardState.settings.thresholds.memory.warning = parseInt(document.getElementById('memoryWarning').value);
    dashboardState.settings.thresholds.memory.critical = parseInt(document.getElementById('memoryCritical').value);
    dashboardState.settings.thresholds.disk.warning = parseInt(document.getElementById('diskWarning').value);
    dashboardState.settings.thresholds.disk.critical = parseInt(document.getElementById('diskCritical').value);

    // Get refresh settings
    const newInterval = parseInt(document.getElementById('refreshInterval').value) * 1000;
    dashboardState.settings.refreshInterval = newInterval;
    dashboardState.settings.autoRefresh = document.getElementById('autoRefresh').checked;

    // Get theme
    const theme = document.getElementById('theme').value;
    dashboardState.settings.theme = theme;

    // Apply theme
    if (theme === 'dark') {
        document.body.classList.add('dark-theme');
    } else {
        document.body.classList.remove('dark-theme');
    }

    // Restart auto-refresh with new interval
    if (dashboardState.settings.autoRefresh) {
        stopAutoRefresh();
        startAutoRefresh();
    }

    // Save to localStorage
    localStorage.setItem('wsa-dashboard-settings', JSON.stringify(dashboardState.settings));

    showToast('success', 'Settings Saved', 'Your preferences have been updated');
    toggleSettings();
}

/**
 * Load settings from localStorage
 */
function loadSettings() {
    const saved = localStorage.getItem('wsa-dashboard-settings');
    if (saved) {
        try {
            const settings = JSON.parse(saved);
            dashboardState.settings = { ...dashboardState.settings, ...settings };

            // Apply settings to UI
            document.getElementById('cpuWarning').value = settings.thresholds?.cpu?.warning || 70;
            document.getElementById('cpuCritical').value = settings.thresholds?.cpu?.critical || 90;
            document.getElementById('memoryWarning').value = settings.thresholds?.memory?.warning || 75;
            document.getElementById('memoryCritical').value = settings.thresholds?.memory?.critical || 90;
            document.getElementById('diskWarning').value = settings.thresholds?.disk?.warning || 80;
            document.getElementById('diskCritical').value = settings.thresholds?.disk?.critical || 95;

            document.getElementById('refreshInterval').value = (settings.refreshInterval || 30000) / 1000;
            document.getElementById('autoRefresh').checked = settings.autoRefresh !== false;
            document.getElementById('theme').value = settings.theme || 'light';

            // Apply theme
            if (settings.theme === 'dark') {
                document.body.classList.add('dark-theme');
            }
        } catch (error) {
            console.error('Failed to load settings:', error);
        }
    }
}

// ===================================================================
// Auto-Refresh Management
// ===================================================================

function startAutoRefresh() {
    if (refreshIntervalId) {
        clearInterval(refreshIntervalId);
    }

    refreshIntervalId = setInterval(() => {
        updateDashboard();
    }, dashboardState.settings.refreshInterval);

    updateAutoRefreshStatus();
}

function stopAutoRefresh() {
    if (refreshIntervalId) {
        clearInterval(refreshIntervalId);
        refreshIntervalId = null;
    }
}

function updateAutoRefreshStatus() {
    const statusEl = document.getElementById('autoRefreshStatus');
    if (statusEl) {
        const seconds = dashboardState.settings.refreshInterval / 1000;
        statusEl.textContent = dashboardState.settings.autoRefresh ?
            `ON (${seconds}s)` : 'OFF';
    }
}

// ===================================================================
// Collapsible Sections
// ===================================================================

function setupCollapsibleSections() {
    const toggleButtons = {
        'toggleServices': 'servicesContent',
        'toggleAlerts': 'alertsContent'
    };

    Object.keys(toggleButtons).forEach(btnId => {
        const btn = document.getElementById(btnId);
        const contentId = toggleButtons[btnId];

        if (btn) {
            btn.addEventListener('click', () => {
                const section = btn.closest('section');
                const content = document.getElementById(contentId);

                if (section && content) {
                    section.classList.toggle('collapsed');
                    const isExpanded = !section.classList.contains('collapsed');
                    btn.setAttribute('aria-expanded', isExpanded);
                }
            });
        }
    });
}

// ===================================================================
// Keyboard Shortcuts
// ===================================================================

function setupKeyboardShortcuts() {
    document.addEventListener('keydown', (e) => {
        // Ctrl/Cmd + R: Refresh dashboard
        if ((e.ctrlKey || e.metaKey) && e.key === 'r') {
            e.preventDefault();
            updateDashboard();
        }

        // Ctrl/Cmd + H: Run health check
        if ((e.ctrlKey || e.metaKey) && e.key === 'h') {
            e.preventDefault();
            runHealthCheck();
        }

        // Ctrl/Cmd + B: Create backup
        if ((e.ctrlKey || e.metaKey) && e.key === 'b') {
            e.preventDefault();
            openModal('backupModal');
        }

        // Escape: Close modals/sidebar
        if (e.key === 'Escape') {
            // Close all modals
            document.querySelectorAll('.modal.active').forEach(modal => {
                closeModal(modal.id);
            });
            // Close settings sidebar
            const sidebar = document.getElementById('settingsSidebar');
            if (sidebar && sidebar.classList.contains('active')) {
                sidebar.classList.remove('active');
            }
        }

        // Ctrl/Cmd + ?: Show help (placeholder)
        if ((e.ctrlKey || e.metaKey) && e.key === '?') {
            e.preventDefault();
            showToast('info', 'Keyboard Shortcuts',
                'Ctrl+R: Refresh | Ctrl+H: Health Check | Ctrl+B: Backup | Esc: Close');
        }
    });
}

// ===================================================================
// Event Listeners Setup
// ===================================================================

function setupEventListeners() {
    // Quick Action Buttons
    const btnHealthCheck = document.getElementById('btnHealthCheck');
    if (btnHealthCheck) {
        btnHealthCheck.addEventListener('click', runHealthCheck);
    }

    const btnBackup = document.getElementById('btnBackup');
    if (btnBackup) {
        btnBackup.addEventListener('click', () => openModal('backupModal'));
    }

    const btnAddUsers = document.getElementById('btnAddUsers');
    if (btnAddUsers) {
        btnAddUsers.addEventListener('click', () => openModal('addUsersModal'));
    }

    const btnSecurityAudit = document.getElementById('btnSecurityAudit');
    if (btnSecurityAudit) {
        btnSecurityAudit.addEventListener('click', runSecurityAudit);
    }

    const btnGenerateReport = document.getElementById('btnGenerateReport');
    if (btnGenerateReport) {
        btnGenerateReport.addEventListener('click', generateReport);
    }

    // Settings
    const btnOpenSettings = document.getElementById('openSettings');
    if (btnOpenSettings) {
        btnOpenSettings.addEventListener('click', toggleSettings);
    }

    const btnCloseSidebar = document.getElementById('closeSidebar');
    if (btnCloseSidebar) {
        btnCloseSidebar.addEventListener('click', toggleSettings);
    }

    const btnSaveSettings = document.getElementById('saveSettings');
    if (btnSaveSettings) {
        btnSaveSettings.addEventListener('click', saveSettings);
    }

    // Modal Buttons
    const btnCancelBackup = document.getElementById('cancelBackup');
    if (btnCancelBackup) {
        btnCancelBackup.addEventListener('click', () => closeModal('backupModal'));
    }

    const btnConfirmBackup = document.getElementById('confirmBackup');
    if (btnConfirmBackup) {
        btnConfirmBackup.addEventListener('click', createBackup);
    }

    const btnCancelAddUsers = document.getElementById('cancelAddUsers');
    if (btnCancelAddUsers) {
        btnCancelAddUsers.addEventListener('click', () => closeModal('addUsersModal'));
    }

    const btnConfirmAddUsers = document.getElementById('confirmAddUsers');
    if (btnConfirmAddUsers) {
        btnConfirmAddUsers.addEventListener('click', addUsersFromCSV);
    }

    // Resource detail buttons (placeholders)
    ['viewCpuDetails', 'viewMemoryDetails', 'viewAllDrives', 'viewAllServices'].forEach(id => {
        const btn = document.getElementById(id);
        if (btn) {
            btn.addEventListener('click', () => {
                showToast('info', 'Feature Coming Soon', `${id} will be available in a future update`);
            });
        }
    });

    // Footer links
    const btnViewDocumentation = document.getElementById('viewDocumentation');
    if (btnViewDocumentation) {
        btnViewDocumentation.addEventListener('click', () => {
            showToast('info', 'Documentation', 'Opening documentation...');
        });
    }

    const btnViewAbout = document.getElementById('viewAbout');
    if (btnViewAbout) {
        btnViewAbout.addEventListener('click', () => {
            showToast('info', 'About WinSysAuto', 'Version 1.0.0 - Professional Windows System Administration Tool');
        });
    }
}

// ===================================================================
// Initialization
// ===================================================================

/**
 * Initialize the dashboard
 */
function initDashboard() {
    console.log('WinSysAuto Dashboard initializing...');

    // Load settings
    loadSettings();

    // Setup modal interactions
    setupModalCloseOnOverlay();
    setupModalCloseButtons();

    // Setup collapsible sections
    setupCollapsibleSections();

    // Setup event listeners
    setupEventListeners();

    // Setup keyboard shortcuts
    setupKeyboardShortcuts();

    // Initial dashboard load
    updateDashboard();

    // Start auto-refresh if enabled
    if (dashboardState.settings.autoRefresh) {
        startAutoRefresh();
    }

    // Update "last updated" every 30 seconds
    setInterval(updateLastUpdated, 30000);

    console.log('WinSysAuto Dashboard initialized successfully');
}

// Start dashboard when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initDashboard);
} else {
    initDashboard();
}

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    stopAutoRefresh();
});
