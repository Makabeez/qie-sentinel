import { concat, hashUtf8, hexToBytes, keccak256, wordAddress, wordUInt } from './keccak-eip712.mjs';

export const domain = Object.freeze({
  name: 'QIE Sentinel Vault V4',
  version: '4',
  chainId: '31337',
  verifyingContract: '0x1000000000000000000000000000000000000001'
});

const paymentFields = [
  ['address', 'token'],
  ['address', 'recipient'],
  ['uint256', 'amount'],
  ['uint256', 'nonce'],
  ['uint256', 'deadline'],
  ['address', 'executor'],
  ['uint256', 'ownerEpoch'],
  ['uint256', 'executorEpoch'],
  ['uint256', 'signerEpoch']
];

const domainType = 'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)';
const paymentType = 'Payment(' + paymentFields.map(field => field.join(' ')).join(',') + ')';

export function paymentDigest(message) {
  const domainSeparator = keccak256(concat(
    hashUtf8(domainType), hashUtf8(domain.name), hashUtf8(domain.version),
    wordUInt(domain.chainId), wordAddress(domain.verifyingContract)
  ));
  const structHash = keccak256(concat(
    hashUtf8(paymentType),
    ...paymentFields.map(([type, name]) => type === 'address'
      ? wordAddress(message[name])
      : wordUInt(message[name]))
  ));
  return keccak256(concat(Uint8Array.of(0x19, 0x01), hexToBytes(domainSeparator), hexToBytes(structHash)));
}
