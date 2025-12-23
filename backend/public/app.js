const dropZone = document.getElementById('dropZone');
const fileInput = document.getElementById('fileInput');
const uploadStatus = document.getElementById('uploadStatus');
const encryptBtn = document.getElementById('encryptBtn');
const encryptionResult = document.getElementById('encryptionResult');
const fileIdDisplay = document.getElementById('fileIdDisplay');
const addToRegistryBtn = document.getElementById('addToRegistryBtn');
const registryList = document.getElementById('registryList');
const manualIdInput = document.getElementById('manualIdInput');
const manualAddBtn = document.getElementById('manualAddBtn');

let uploadedFileName = null;
let generatedFileId = null;

// --- Upload Logic ---
dropZone.addEventListener('click', () => fileInput.click());

fileInput.addEventListener('change', (e) => handleFiles(e.target.files));
dropZone.addEventListener('dragover', (e) => { e.preventDefault(); dropZone.style.borderColor = '#3b82f6'; });
dropZone.addEventListener('dragleave', (e) => { e.preventDefault(); dropZone.style.borderColor = '#444'; });
dropZone.addEventListener('drop', (e) => {
    e.preventDefault();
    dropZone.style.borderColor = '#444';
    handleFiles(e.dataTransfer.files);
});

function handleFiles(files) {
    if (files.length === 0) return;
    const file = files[0];
    uploadFile(file);
}

async function uploadFile(file) {
    uploadStatus.textContent = `Uploading ${file.name}...`;
    encryptBtn.disabled = true;

    const formData = new FormData();
    formData.append('video', file);

    try {
        const res = await fetch('/api/upload', {
            method: 'POST',
            body: formData
        });
        const data = await res.json();

        if (data.success) {
            uploadStatus.textContent = `✅ Uploaded: ${data.fileName}`;
            uploadedFileName = data.fileName;
            encryptBtn.disabled = false;
        } else {
            uploadStatus.textContent = `❌ Upload Failed: ${data.message}`;
        }
    } catch (e) {
        uploadStatus.textContent = `❌ Error: ${e.message}`;
    }
}

// --- Encrypt Logic ---
encryptBtn.addEventListener('click', async () => {
    if (!uploadedFileName) return;

    uploadStatus.textContent = "Encrypting... This may take a moment.";
    encryptBtn.disabled = true;

    try {
        const res = await fetch('/api/encrypt', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ fileName: uploadedFileName })
        });
        const data = await res.json();

        if (data.success) {
            uploadStatus.textContent = "✅ Encryption Complete!";
            generatedFileId = data.fileId;
            fileIdDisplay.textContent = generatedFileId;
            encryptionResult.classList.remove('hidden');
        } else {
            uploadStatus.textContent = `❌ Encryption Failed: ${data.message}`;
            encryptBtn.disabled = false;
        }
    } catch (e) {
        uploadStatus.textContent = `❌ Error: ${e.message}`;
        encryptBtn.disabled = false;
    }
});

// --- Registry Logic ---
async function fetchRegistry() {
    try {
        const res = await fetch('/api/registry');
        const data = await res.json();
        renderRegistry(data.allowed_files);
    } catch (e) {
        console.error("Failed to fetch registry:", e);
    }
}

function renderRegistry(files) {
    registryList.innerHTML = '';
    files.forEach(id => {
        const li = document.createElement('li');
        li.className = 'file-item';
        li.innerHTML = `
            <span>${id}</span>
            <button class="btn danger" onclick="removeId('${id}')">Revoke</button>
        `;
        registryList.appendChild(li);
    });
}

async function addId(id) {
    if (!id) return;
    try {
        const res = await fetch('/api/registry/add', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ fileId: id })
        });
        const data = await res.json();
        if (data.success) {
            renderRegistry(data.registry.allowed_files);
            manualIdInput.value = '';
        }
    } catch (e) {
        console.error("Error adding ID", e);
    }
}

async function removeId(id) {
    if (!confirm(`Are you sure you want to revoke access for ${id}?`)) return;
    try {
        const res = await fetch('/api/registry/remove', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ fileId: id })
        });
        const data = await res.json();
        if (data.success) {
            renderRegistry(data.registry.allowed_files);
        }
    } catch (e) {
        console.error("Error removing ID", e);
    }
}

// Global scope for onclick
window.removeId = removeId;

addToRegistryBtn.addEventListener('click', () => {
    if (generatedFileId) addId(generatedFileId);
});

manualAddBtn.addEventListener('click', () => {
    addId(manualIdInput.value.trim());
});

// Init
fetchRegistry();
