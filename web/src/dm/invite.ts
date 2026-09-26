// The addresses players join at, as the host ranks them (WebServer.address_rank
// in hexmap/net/web_server.gd): the likeliest first, and each of the others
// said for what it is. (A playtest's DM, her players in four places, saw four
// addresses and "the same Wi-Fi", and worried before anyone had joined.)

/** The IPv4 address in a join address ("http://192.168.1.23:47780"). */
function hostOf(address: string): string {
  return address.replace(/^[a-z]+:\/\//i, '').split(/[:/]/)[0] ?? '';
}

/** How likely other devices reach this computer there: 0 a private network,
 * 1 a virtual machine's (one of Parallels' own subnets, or a private
 * network's .1, usually this computer's side of a virtual machine's; the
 * host also puts addresses on virtual interfaces last), 2 an overlay network
 * (100.64/10, a VPN's), 3 anything else. */
export function addressRank(address: string): number {
  const p = hostOf(address).split('.');
  if (p.length !== 4 || p.some((x) => !/^\d{1,3}$/.test(x))) return 3;
  const a = Number(p[0]);
  const b = Number(p[1]);
  if (a === 100 && b >= 64 && b < 128) return 2;
  if (a === 10 && ((b === 211 && Number(p[2]) === 55) || (b === 37 && Number(p[2]) === 129))) return 1;
  const isPrivate = a === 10 || (a === 192 && b === 168) || (a === 172 && b >= 16 && b < 32);
  if (isPrivate) return p[3] === '1' ? 1 : 0;
  return 3;
}

const KINDS = ['a home or office network', 'a virtual machine’s (rarely right)', 'a VPN such as Tailscale', 'another network'];

/** What one of this computer's addresses is, in words. */
export function addressKind(address: string): string {
  return KINDS[addressRank(address)];
}
