// QIE Sentinel 2.4 — dependency-free Keccak-256 and exact EIP-712 Payment digest.
// This module computes hashes in-browser, independently of the QIE RPC.
// It deliberately has NO wallet, signing, or network functionality.
import {encodeDigestCall} from './freshness.mjs';
const MASK=(1n<<64n)-1n;
const ROT=[
  0,1,62,28,27,
  36,44,6,55,20,
  3,10,43,25,39,
  41,45,15,21,8,
  18,2,61,56,14
]; // x + 5*y indexing, FIPS-202 rho matrix transposed to lanes
const RC=[
  0x0000000000000001n,0x0000000000008082n,0x800000000000808an,0x8000000080008000n,
  0x000000000000808bn,0x0000000080000001n,0x8000000080008081n,0x8000000000008009n,
  0x000000000000008an,0x0000000000000088n,0x0000000080008009n,0x000000008000000an,
  0x000000008000808bn,0x800000000000008bn,0x8000000000008089n,0x8000000000008003n,
  0x8000000000008002n,0x8000000000000080n,0x000000000000800an,0x800000008000000an,
  0x8000000080008081n,0x8000000000008080n,0x0000000080000001n,0x8000000080008008n
];
function rot(x,n){const k=BigInt(n);return k===0n?x:((x<<k)|(x>>(64n-k)))&MASK;}
function permute(a){
 for(const rc of RC){
  const c=new Array(5),d=new Array(5),b=new Array(25);
  for(let x=0;x<5;x++)c[x]=a[x]^a[x+5]^a[x+10]^a[x+15]^a[x+20];
  for(let x=0;x<5;x++)d[x]=c[(x+4)%5]^rot(c[(x+1)%5],1);
  for(let i=0;i<25;i++)a[i]^=d[i%5];
  for(let y=0;y<5;y++)for(let x=0;x<5;x++){
   const i=x+5*y;
   b[y+5*((2*x+3*y)%5)]=rot(a[i],ROT[i]);
  }
  for(let y=0;y<5;y++)for(let x=0;x<5;x++)
   a[x+5*y]=b[x+5*y]^((~b[(x+1)%5+5*y])&b[(x+2)%5+5*y]);
  a[0]^=rc;
 }
}
export function hexToBytes(hex){
 if(typeof hex!=='string'||!/^0x(?:[0-9a-fA-F]{2})*$/.test(hex))throw new Error('Invalid hex data');
 return Uint8Array.from(hex.slice(2).match(/.{2}/g)?.map(v=>parseInt(v,16))??[]);
}
function bytesToHex(bytes){return '0x'+Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');}
export function concat(...xs){const n=xs.reduce((s,x)=>s+x.length,0),r=new Uint8Array(n);let i=0;for(const x of xs){r.set(x,i);i+=x.length;}return r;}
function utf8(s){return new TextEncoder().encode(s);}
export function keccak256(data){
 if(!(data instanceof Uint8Array))throw new TypeError('keccak256 expects Uint8Array');
 const rate=136,a=Array(25).fill(0n),length=data.length;
 const size=Math.ceil((length+1)/rate)*rate||rate, padded=new Uint8Array(size);
 padded.set(data);padded[length]^=0x01;padded[size-1]^=0x80; // Ethereum Keccak, not SHA3
 for(let offset=0;offset<size;offset+=rate){
  for(let i=0;i<rate;i++)a[Math.floor(i/8)]^=BigInt(padded[offset+i])<<BigInt(8*(i%8));
  permute(a);
 }
 const out=new Uint8Array(32);
 for(let i=0;i<32;i++)out[i]=Number((a[Math.floor(i/8)]>>BigInt(8*(i%8)))&255n);
 return bytesToHex(out);
}
export function hashUtf8(s){return hexToBytes(keccak256(utf8(s)));}
export function wordAddress(value){
 if(typeof value!=='string'||!/^0x[0-9a-fA-F]{40}$/.test(value))throw new Error('Invalid address');
 return hexToBytes('0x'+'0'.repeat(24)+value.slice(2));
}
export function wordUInt(value){
 if(typeof value!=='string'||!/^(0|[1-9][0-9]*)$/.test(value))throw new Error('Noncanonical uint256');
 const n=BigInt(value);if(n>=(1n<<256n))throw new Error('uint256 overflow');
 return hexToBytes('0x'+n.toString(16).padStart(64,'0'));
}
export function offlineEip712(packet){
 // Validate exact expected vault, domain and canonical message first.
 encodeDigestCall(packet);
 const domain=packet.typedData.domain,m=packet.typedData.message;
 // Reject malformed EIP712Domain metadata in imported, user-controlled JSON.
 const meta=packet.typedData.types?.EIP712Domain;
 const domainFields=['name','version','chainId','verifyingContract'];
 const domainTypes=['string','string','uint256','address'];
 if(!Array.isArray(meta)||meta.length!==4||
    meta.some((entry,i)=>entry?.name!==domainFields[i]||entry?.type!==domainTypes[i]))
   throw new Error('Noncanonical EIP712Domain fields');
 const domainKeys=Object.keys(domain).sort();
 if(domainKeys.join(',')!==domainFields.slice().sort().join(','))
   throw new Error('Unexpected domain metadata');
 const messageKeys=Object.keys(m).sort();
 if(messageKeys.join(',')!==['token','recipient','amount','nonce','deadline','executor'].sort().join(','))
   throw new Error('Unexpected payment fields');
 const dh=keccak256(concat(
  hashUtf8('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
  hashUtf8(domain.name),hashUtf8(domain.version),
  wordUInt(String(domain.chainId)),wordAddress(domain.verifyingContract)
 ));
 const sh=keccak256(concat(
  hashUtf8('Payment(address token,address recipient,uint256 amount,uint256 nonce,uint256 deadline,address executor)'),
  wordAddress(m.token),wordAddress(m.recipient),wordUInt(m.amount),
  wordUInt(m.nonce),wordUInt(m.deadline),wordAddress(m.executor)
 ));
 const digest=keccak256(concat(new Uint8Array([0x19,0x01]),hexToBytes(dh),hexToBytes(sh)));
 return {digest,domainSeparator:dh,structHash:sh,algorithm:'Ethereum Keccak-256, EIP-712 v4; independently computed without RPC'};
}
export function compareEip712(packet,chainDigest,chainDomain){
 const offline=offlineEip712(packet);
 const equal=typeof chainDigest==='string'&&typeof chainDomain==='string'&&
   offline.digest.toLowerCase()===chainDigest.toLowerCase()&&
   offline.domainSeparator.toLowerCase()===chainDomain.toLowerCase();
 return {...offline,onchainDigest:chainDigest,onchainDomainSeparator:chainDomain,match:equal};
}
