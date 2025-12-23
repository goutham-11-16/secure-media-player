const express = require('express');
const cors = require('cors');
const crypto = require("crypto");
const bodyParser = require('body-parser');
const fs = require('fs');
const readline = require('readline');
const path = require('path');
const multer = require('multer');

const app = express();
const PORT = 3000;
const REGISTRY_FILE = path.join(__dirname, 'file_registry.json');
const UPLOAD_DIR = path.join(__dirname, 'uploads');

// Ensure upload directory exists
if (!fs.existsSync(UPLOAD_DIR)) {
    fs.mkdirSync(UPLOAD_DIR);
}

app.use(cors());
app.use(bodyParser.json());
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

const VALID_TOKENS = ['secure-token-123', 'admin-secret'];

const PASSWORD = process.env.VIDEO_PASSWORD || 'Goutham@111620';

if (!process.env.VIDEO_PASSWORD) {
    console.warn("WARNING: VIDEO_PASSWORD not set. Using default: Goutham@111620");
}

const KEY = crypto.createHash("sha256")
    .update(PASSWORD)
    .digest();

const IV = crypto.createHash("md5")
    .update(PASSWORD)
    .digest();

// --- File Registry Logic ---
class FileRegistry {
    constructor(filePath) {
        this.filePath = filePath;
        this.allowedFiles = new Set();
        this.load();
    }

    load() {
        if (fs.existsSync(this.filePath)) {
            try {
                const data = fs.readFileSync(this.filePath, 'utf8');
                const json = JSON.parse(data);
                if (Array.isArray(json.allowed_files)) {
                    this.allowedFiles = new Set(json.allowed_files);
                    console.log(`[Registry] Loaded ${this.allowedFiles.size} allowed file IDs.`);
                }
            } catch (e) {
                console.error("[Registry] Error loading registry:", e.message);
            }
        } else {
            console.log("[Registry] No registry file found. Starting empty.");
            this.save();
        }
    }

    save() {
        try {
            const data = JSON.stringify({ allowed_files: Array.from(this.allowedFiles) }, null, 4);
            fs.writeFileSync(this.filePath, data);
        } catch (e) {
            console.error("[Registry] Error saving registry:", e.message);
        }
    }

    add(fileId) {
        if (!fileId) return false;
        this.allowedFiles.add(fileId);
        this.save();
        console.log(`[Registry] Added: ${fileId}`);
        return true;
    }

    remove(fileId) {
        if (this.allowedFiles.delete(fileId)) {
            this.save();
            console.log(`[Registry] Removed: ${fileId}`);
            return true;
        }
        return false;
    }

    isAllowed(fileId) {
        return this.allowedFiles.has(fileId);
    }

    list() {
        return Array.from(this.allowedFiles);
    }
}

const registry = new FileRegistry(REGISTRY_FILE);

// --- CLI Logic ---
const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt: 'SERVER> '
});

rl.on('line', (line) => {
    const args = line.trim().split(' ');
    const command = args[0].toLowerCase();
    const arg = args[1];

    switch (command) {
        case 'help':
            console.log("Commands: list, add <id>, remove <id>, quit");
            break;
        case 'list':
            const files = registry.list();
            console.log("Allowed File IDs:");
            if (files.length === 0) console.log("  (none)");
            files.forEach(id => console.log(`  - ${id}`));
            break;
        case 'add':
            if (arg) registry.add(arg);
            else console.log("Usage: add <file_id>");
            break;
        case 'remove':
            if (arg) registry.remove(arg);
            else console.log("Usage: remove <file_id>");
            break;
        case 'quit':
        case 'exit':
            console.log("Shutting down...");
            process.exit(0);
            break;
        default:
            if (line.trim()) console.log("Unknown command. Type 'help'.");
            break;
    }
    rl.prompt();
});

// --- Server Routes ---

// 1. Auth Endpoint (Player)
app.post("/auth", (req, res) => {
    console.log("Auth request:", req.body);
    const { token, file_id } = req.body;

    if (!token || !file_id) {
        return res.status(400).json({ success: false, message: "Missing token or file_id" });
    }

    if (!VALID_TOKENS.includes(token)) {
        return res.status(401).json({ success: false, message: "Invalid session token" });
    }

    if (!registry.isAllowed(file_id)) {
        console.log(`[Auth Denied] Blocked request for file ID: ${file_id}`);
        return res.status(403).json({ success: false, message: "Unauthorized File ID" });
    }

    console.log(`[Auth Granted] Token: ${token}, File: ${file_id}`);
    res.json({
        success: true,
        session_key: KEY.toString("base64"),
        iv: IV.toString("base64")
    });
});

app.get('/status', (req, res) => {
    res.json({ status: 'online', service: 'Server Player Auth' });
});

// 2. Admin API Endpoints

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
    // Hash is calculated after encryption

    input.pipe(cipher).pipe(output);

    output.on('finish', () => {
        console.log(`[Admin] Encryption done. Calculating hash...`);

        // Calculate Hash of Encrypted File
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

// Registry API
app.get('/api/registry', (req, res) => {
    res.json({ allowed_files: registry.list() });
});

app.post('/api/registry/add', (req, res) => {
    const { fileId } = req.body;
    if (registry.add(fileId)) {
        res.json({ success: true, registry: { allowed_files: registry.list() } });
    } else {
        res.status(400).json({ success: false });
    }
});

app.post('/api/registry/remove', (req, res) => {
    const { fileId } = req.body;
    if (registry.remove(fileId)) {
        res.json({ success: true, registry: { allowed_files: registry.list() } });
    } else {
        res.status(400).json({ success: false });
    }
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server running on http://0.0.0.0:${PORT}`);
    console.log(`- Player Auth: http://0.0.0.0:${PORT}/auth`);
    console.log(`- Admin Panel: http://0.0.0.0:${PORT}/`);

    console.log(`[DEBUG] Key Hash (Starts with): ${KEY.toString('hex').substring(0, 8)}...`);
    console.log(`[DEBUG] IV Hash (Starts with): ${IV.toString('hex').substring(0, 8)}...`);

    setTimeout(() => {
        console.log("\n--- File Permission Control ---");
        console.log("Type 'help' for commands.");
        rl.prompt();
    }, 1000);
});
