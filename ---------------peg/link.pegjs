// 102.20.49.49
// aa:bb:cc:dd

TEXT = (url_address / space_or_newline+)*

url_address = IPv6Adr / IPv4Adr

UriEnecoded
  = & "%" Encoded:("%"[0-9A-Fa-f][0-9A-Fa-f])
 {
  try { return decodeURIComponent(Encoded.join("")) }
  catch { return null }
 }

IPv4Adr
  = $(IPv4Field "." IPv4Field "." IPv4Field "." IPv4Field url_port?)

IPv4Field
  =
   & "%" E:UriEnecoded { return E }
   /
  $( ("25"[0-5]) / ("2"[0-4][0-9]) / ("1"[0-9][0-9]) / ([1-9]?[0-9]) )

IPv6Adr
  = (
      (
        ("%5B" / "[") Adr:IPv6Address ("%5D" / "]") {return Adr }
      )
      url_port?
    )
    / IPv6Address

IPv6Address
  = Adr:(IPv6Field ":" IPv6Field ":" IPv6Field ":" IPv6Field)
  { return "[" + Adr.join("") + "]" }

IPv6Field
  = $ ([0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?)

url_port = ":" p:[0-9]+ { return ":" + p.join("")}

space_or_newline = [ \t\n\r\x0c] { return null }
