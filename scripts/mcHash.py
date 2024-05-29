# macdr in **little-endian** representation as a long int
# e.g., 01:02:03:04:05:06 =>  0x060504030201
def mcHash(mcAddr, le_poly=0x33):
  h = 0
  for i in range(48):
    s = (mcAddr & 1)
    mcAddr >>= 1
    if s != 0:
       mcAddr ^= le_poly
  return mcAddr
