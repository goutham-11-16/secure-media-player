const express = require('express');
const cors = require('cors');
const multer = require('multer');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const app = express();
const PORT = 3001; // Admin Server Port
const REGISTRY_FILE = path.join(__dirname, 'file_registry.json');
const UPLOAD_DIR = path.join(__dirname, 'uploads');
const VIDEO_DIR = __dirname; // Keep encrypted videos in root for now, or move to 'videos/'

// Ensure upload directory exists
if (!fs.existsSync(UPLOAD_DIR)) {
    fs.mkdirSync(UPLOAD_DIR);
}

app.use(cors());
app.use(express.json());
app.use(express.static('public')); // Serve Admin Dashboard

// Multer Storage
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, UPLOAD_DIR);
    },
    filename: (req, file, cb) => {
        cb(null, file.originalname);
    }
});
const upload = multer({ storage: storage });

const PASSWORD = process.env.VIDEO_PASSWORD || 'Goutham@111620';
const KEY = crypto.createHash("sha256").update(PASSWORD).digest();
const IV = crypto.createHash("md5").update(PASSWORD).digest();

// --- Helper Functions ---

function loadRegistry() {
    if (fs.existsSync(REGISTRY_FILE)) {
        try {
            return JSON.parse(fs.readFileSync(REGISTRY_FILE, 'utf8'));
        } catch (e) {
            return { allowed_files: [] };
        }
    }
    return { allowed_files: [] };
}

function saveRegistry(data) {
    fs.writeFileSync(REGISTRY_FILE, JSON.stringify(data, null, 4));
}

// --- Routes ---

// Upload Video
app.post('/api/upload', upload.single('video'), (req, res) => {
    if (!req.file) {
        return res.status(400).json({ success: false, message: 'No file uploaded' });
    }
    console.log(`[Admin] Uploaded: ${req.file.path}`);
    res.json({ success: true, filePath: req.file.path, fileName: req.file.originalname });
});

// Encrypt Video
app.post('/api/encrypt', (req, res) => {
    const { fileName, outputDir } = req.body;
    if (!fileName) return res.status(400).json({ success: false, message: 'Missing fileName' });

    const inputPath = path.join(UPLOAD_DIR, fileName);

    // Determine Output Path
    let finalOutputPath;
    if (outputDir && outputDir.trim() !== "") {
        try {
            if (!fs.existsSync(outputDir)) {
                fs.mkdirSync(outputDir, { recursive: true });
            }
            finalOutputPath = path.join(outputDir, fileName + '.bin');
        } catch (e) {
            return res.status(500).json({ success: false, message: `Invalid Output Dir: ${e.message}` });
        }
    } else {
        // Default to root backend folder
        finalOutputPath = path.join(__dirname, fileName + '.bin');
    }

    const outputPath = finalOutputPath;

    if (!fs.existsSync(inputPath)) {
        return res.status(404).json({ success: false, message: 'File not found' });
    }

    console.log(`[Admin] Encrypting ${inputPath} to ${outputPath}...`);

    const cipher = crypto.createCipheriv("aes-256-cbc", KEY, IV);
    const input = fs.createReadStream(inputPath);
    const output = fs.createWriteStream(outputPath);
    const hash = crypto.createHash('sha256');

    // Create a passthrough stream to calculate hash while encrypting?
    // Usually easier to encrypt first, then hash the OUTPUT file as per req.
    // Req said: "File ID, derived from: A cryptographic hash of the encrypted file"

    input.pipe(cipher).pipe(output);

    output.on('finish', () => {
        console.log(`[Admin] Encryption done. Calculating hash...`);

        // Calculate Hash of Encrypted File
        const fileStream = fs.createReadStream(outputPath);
        const hashStream = crypto.createHash('sha256');

        fileStream.pipe(hashStream);

        hashStream.on('finish', () => { // Wait, hashStream is Writable.
            // crypto.createHash returns a Transform/Hash object. 
            // We can read from it or use setEncoding('hex').
            // simplified:
        });

        // Let's do it simpler.
        const fd = fs.createReadStream(outputPath);
        const h = crypto.createHash('sha256');
        fd.on('data', d => h.update(d));
        fd.on('end', () => {
            const fileId = h.digest('hex');
            console.log(`[Admin] File ID: ${fileId}`);
            res.json({ success: true, fileId: fileId, message: "Encryption successful" });
        });
    });

    output.on('error', (err) => {
        console.error("Encryption error:", err);
        res.status(500).json({ success: false, message: "Encryption failed" });
    });
});

// Registry Management
app.get('/api/registry', (req, res) => {
    const reg = loadRegistry();
    res.json(reg);
});

app.post('/api/registry/add', (req, res) => {
    const { fileId } = req.body;
    if (!fileId) return res.status(400).json({ success: false });

    const reg = loadRegistry();
    if (!reg.allowed_files.includes(fileId)) {
        reg.allowed_files.push(fileId);
        saveRegistry(reg);
        console.log(`[Admin] Added ID: ${fileId}`);
    }
    res.json({ success: true, registry: reg });
});

app.post('/api/registry/remove', (req, res) => {
    const { fileId } = req.body;
    if (!fileId) return res.status(400).json({ success: false });

    const reg = loadRegistry();
    reg.allowed_files = reg.allowed_files.filter(id => id !== fileId);
    saveRegistry(reg);
    console.log(`[Admin] Removed ID: ${fileId}`);
    res.json({ success: true, registry: reg });
});


app.listen(PORT, '0.0.0.0', () => {
    console.log(`Admin Server running on http://0.0.0.0:${PORT}`);
});
