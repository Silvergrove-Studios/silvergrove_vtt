import { describe, expect, it } from 'vitest';
import { addressKind, addressRank } from '../src/dm/invite';

describe('the addresses players join at', () => {
  it('ranks them as the host does (WebServer.address_rank)', () => {
    // the host's own test's addresses, and the other private ranges
    expect(addressRank('192.168.1.23')).toBe(0);
    expect(addressRank('10.5.91.189')).toBe(0);
    expect(addressRank('172.20.0.7')).toBe(0);
    expect(addressRank('192.168.18.1')).toBe(1);
    // Parallels' shared and host-only networks (this Mac's own address there ends .2)
    expect(addressRank('10.211.55.2')).toBe(1);
    expect(addressRank('10.37.129.2')).toBe(1);
    expect(addressRank('100.99.188.26')).toBe(2);
    expect(addressRank('8.8.8.8')).toBe(3);
    expect(addressRank('172.32.0.7')).toBe(3);
    expect(addressRank('fe80::1')).toBe(3);
  });
  it('reads a join address as its host', () => {
    expect(addressRank('http://192.168.1.23:47780')).toBe(0);
    expect(addressRank('http://100.99.188.26:47780/')).toBe(2);
  });
  it('says what each one is', () => {
    expect(addressKind('http://192.168.1.23:47780')).toBe('a home or office network');
    expect(addressKind('http://192.168.18.1:47780')).toBe('a virtual machine’s (rarely right)');
    expect(addressKind('http://100.99.188.26:47780')).toBe('a VPN such as Tailscale');
    expect(addressKind('http://8.8.8.8:47780')).toBe('another network');
  });
});
