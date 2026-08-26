import * as secp from "https://cdn.jsdelivr.net/npm/@noble/secp256k1@1.7.1/+esm";
 
// Helper function to convert signature to DER format
function signatureToDER(r, s) {
  // Convert r and s to byte arrays with proper length
  let rBytes = secp.utils.hexToBytes(r.padStart(64, '0'));
  let sBytes = secp.utils.hexToBytes(s.padStart(64, '0'));
  
  // Remove leading zeros
  while (rBytes[0] === 0 && rBytes.length > 1) rBytes = rBytes.slice(1);
  while (sBytes[0] === 0 && sBytes.length > 1) sBytes = sBytes.slice(1);
  
  // Check if first byte has high bit set, if so prepend 0x00
  if (rBytes[0] & 0x80) rBytes = [0, ...rBytes];
  if (sBytes[0] & 0x80) sBytes = [0, ...sBytes];
  
  // Calculate lengths
  const rLen = rBytes.length;
  const sLen = sBytes.length;
  
  // Build DER structure
  const result = [
    0x30, // SEQUENCE tag
    rLen + sLen + 4, // total length
    0x02, // INTEGER tag for r
    rLen, // r length
    ...rBytes, // r value
    0x02, // INTEGER tag for s
    sLen, // s length
    ...sBytes // s value
  ];
  
  return new Uint8Array(result);
}

// THIS IS THE FUNCTION CALLED FROM DART
window.secpSign = async function(privateKeyHex, messageHex) {
  try {
    // Sign the message with canonical low-S value
    const signature = await secp.sign(messageHex, privateKeyHex, { canonical: true, der: false });
    
    // Convert the 64-byte signature to r,s components
    const sigHex = secp.utils.bytesToHex(signature);
    const r = sigHex.slice(0, 64);
    const s = sigHex.slice(64, 128);
    
    // Convert to DER format - return bytes directly instead of hex string
    return signatureToDER(r, s);
  } catch (error) {
    console.error("Error in secp256k1 signing:", error);
    throw error;
  }
}; 