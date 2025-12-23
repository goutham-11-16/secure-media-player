const crypto = require("crypto");
const fs = require("fs");

const PASSWORD = process.env.VIDEO_PASSWORD || 'Goutham@111620';

if (!process.env.VIDEO_PASSWORD) {
    console.warn("WARNING: VIDEO_PASSWORD not set. Using default: Goutham@111620");
}

// 32 bytes key
const KEY = crypto.createHash("sha256")
    .update(PASSWORD)
    .digest();

// 16 bytes IV
const IV = crypto.createHash("md5")
    .update(PASSWORD)
    .digest();

function encryptFile(inputPath) {
    if (!fs.existsSync(inputPath)) {
        console.error("File not found:", inputPath);
        return;
    }
    const cipher = crypto.createCipheriv("aes-256-cbc", KEY, IV);
    console.log(`[DEBUG] Key Hash (Starts with): ${KEY.toString('hex').substring(0, 8)}...`);
    console.log(`[DEBUG] IV Hash (Starts with): ${IV.toString('hex').substring(0, 8)}...`);
    const output = fs.createWriteStream(inputPath + ".bin");

    fs.createReadStream(inputPath)
        .pipe(cipher)
        .pipe(output);

    output.on('finish', () => {
        const encryptedPath = inputPath + ".bin";
        console.log(`Encrypted to ${encryptedPath}`);

        // Calculate Hash for Registry
        const hash = crypto.createHash('sha256');
        const stream = fs.createReadStream(encryptedPath);

        stream.on('data', (data) => hash.update(data));
        stream.on('end', () => {
            const fileId = hash.digest('hex');
            console.log(`\n-----------------------------------------------------------`);
            console.log(`[IMPORTANT] File ID: ${fileId}`);
            console.log(`Run this on the server to allow playback:\n\n  add ${fileId}\n`);
            console.log(`-----------------------------------------------------------`);
        });
    });
}

const file = process.argv[2];
if (file) {
    encryptFile(file);
} else {
    console.log("Usage: node encrypt_file.js <file>");
}
