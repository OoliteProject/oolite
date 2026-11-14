/*
	Minimal zip reading and writing for OXZ files: stored and deflated
	entries, no encryption, no zip64. Unchanged entries are copied with their
	original compressed data, flags and timestamps.
*/

"use strict";

const zlib = require("zlib");

const CRC_TABLE = (() => {
	const table = new Uint32Array(256);
	for (let n = 0; n < 256; n++) {
		let c = n;
		for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
		table[n] = c >>> 0;
	}
	return table;
})();

function crc32(buffer)
{
	let crc = 0xFFFFFFFF;
	for (let i = 0; i < buffer.length; i++) crc = CRC_TABLE[(crc ^ buffer[i]) & 0xFF] ^ (crc >>> 8);
	return (crc ^ 0xFFFFFFFF) >>> 0;
}

function readZip(buffer)
{
	// Find the end of central directory record.
	let eocd = -1;
	for (let i = buffer.length - 22; i >= Math.max(0, buffer.length - 22 - 0xFFFF); i--) {
		if (buffer.readUInt32LE(i) === 0x06054B50) { eocd = i; break; }
	}
	if (eocd < 0) throw new Error("not a zip file");
	const count = buffer.readUInt16LE(eocd + 10);
	let offset = buffer.readUInt32LE(eocd + 16);
	const entries = [];
	for (let i = 0; i < count; i++) {
		if (buffer.readUInt32LE(offset) !== 0x02014B50) throw new Error("bad central directory");
		const entry = {
			versionMadeBy: buffer.readUInt16LE(offset + 4),
			versionNeeded: buffer.readUInt16LE(offset + 6),
			flags: buffer.readUInt16LE(offset + 8),
			method: buffer.readUInt16LE(offset + 10),
			time: buffer.readUInt16LE(offset + 12),
			date: buffer.readUInt16LE(offset + 14),
			crc: buffer.readUInt32LE(offset + 16),
			compressedSize: buffer.readUInt32LE(offset + 20),
			size: buffer.readUInt32LE(offset + 24),
			internalAttributes: buffer.readUInt16LE(offset + 36),
			externalAttributes: buffer.readUInt32LE(offset + 38),
		};
		const nameLength = buffer.readUInt16LE(offset + 28);
		const extraLength = buffer.readUInt16LE(offset + 30);
		const commentLength = buffer.readUInt16LE(offset + 32);
		const localOffset = buffer.readUInt32LE(offset + 42);
		entry.nameBytes = buffer.subarray(offset + 46, offset + 46 + nameLength);
		entry.name = entry.nameBytes.toString(entry.flags & 0x800 ? "utf8" : "latin1");
		offset += 46 + nameLength + extraLength + commentLength;

		if (buffer.readUInt32LE(localOffset) !== 0x04034B50) throw new Error(`bad local header for ${entry.name}`);
		const localName = buffer.readUInt16LE(localOffset + 26);
		const localExtra = buffer.readUInt16LE(localOffset + 28);
		const dataStart = localOffset + 30 + localName + localExtra;
		entry.compressed = buffer.subarray(dataStart, dataStart + entry.compressedSize);
		entries.push(entry);
	}
	return entries;
}

function entryData(entry)
{
	if (entry.method === 0) return entry.compressed;
	if (entry.method === 8) return zlib.inflateRawSync(entry.compressed);
	throw new Error(`${entry.name}: unsupported compression method ${entry.method}`);
}

// Replaces an entry's contents, deflating it.
function setEntryData(entry, data)
{
	entry.compressed = zlib.deflateRawSync(data, { level: 9 });
	entry.method = 8;
	entry.flags &= ~0x8; // No data descriptor.
	entry.crc = crc32(data);
	entry.size = data.length;
	entry.compressedSize = entry.compressed.length;
	entry.versionNeeded = Math.max(entry.versionNeeded, 20);
}

function writeZip(entries)
{
	const parts = [];
	const central = [];
	let offset = 0;
	for (const entry of entries) {
		const flags = entry.flags & ~0x8;
		const local = Buffer.alloc(30);
		local.writeUInt32LE(0x04034B50, 0);
		local.writeUInt16LE(entry.versionNeeded, 4);
		local.writeUInt16LE(flags, 6);
		local.writeUInt16LE(entry.method, 8);
		local.writeUInt16LE(entry.time, 10);
		local.writeUInt16LE(entry.date, 12);
		local.writeUInt32LE(entry.crc, 14);
		local.writeUInt32LE(entry.compressedSize, 18);
		local.writeUInt32LE(entry.size, 22);
		local.writeUInt16LE(entry.nameBytes.length, 26);
		local.writeUInt16LE(0, 28);
		parts.push(local, entry.nameBytes, entry.compressed);

		const header = Buffer.alloc(46);
		header.writeUInt32LE(0x02014B50, 0);
		header.writeUInt16LE(entry.versionMadeBy, 4);
		header.writeUInt16LE(entry.versionNeeded, 6);
		header.writeUInt16LE(flags, 8);
		header.writeUInt16LE(entry.method, 10);
		header.writeUInt16LE(entry.time, 12);
		header.writeUInt16LE(entry.date, 14);
		header.writeUInt32LE(entry.crc, 16);
		header.writeUInt32LE(entry.compressedSize, 20);
		header.writeUInt32LE(entry.size, 24);
		header.writeUInt16LE(entry.nameBytes.length, 28);
		header.writeUInt16LE(0, 30);
		header.writeUInt16LE(0, 32);
		header.writeUInt16LE(0, 34);
		header.writeUInt16LE(entry.internalAttributes, 36);
		header.writeUInt32LE(entry.externalAttributes, 38);
		header.writeUInt32LE(offset, 42);
		central.push(header, entry.nameBytes);

		offset += local.length + entry.nameBytes.length + entry.compressed.length;
	}
	const centralSize = central.reduce((n, b) => n + b.length, 0);
	const end = Buffer.alloc(22);
	end.writeUInt32LE(0x06054B50, 0);
	end.writeUInt16LE(entries.length, 8);
	end.writeUInt16LE(entries.length, 10);
	end.writeUInt32LE(centralSize, 12);
	end.writeUInt32LE(offset, 16);
	return Buffer.concat([...parts, ...central, end]);
}

module.exports = { readZip, writeZip, entryData, setEntryData, crc32 };
