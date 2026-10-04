# Third-party notices

Bus Stop is released under the MIT License (see [LICENSE](LICENSE)). It builds on the published work of the projects below. Their licences require the copyright notice and permission notice to be included with copies or substantial portions of their software, so each is reproduced here in full.

Every build made by `scripts/build-app.sh` carries this file and Bus Stop's licence (as `LICENSE.txt`) in `Bus Stop.app/Contents/Resources`, and the release zip holds both again next to the app.

Files in this repository that adapt code from one of these projects say so in a comment at the top, in the form "Portions adapted from <project> (MIT License, © <year> <author>)."

No code licensed under the GPL or another copyleft licence is included in Bus Stop.

---

## PortScope

- Project: https://github.com/azenla/portscope
- Used for: the per-model catalogue of physical port locations (`MacPortLocations.json`), converted to Swift by `scripts/generate-port-catalog.py` into `Sources/BusStopCore/Labels/PortLocationCatalog+Data.swift`. Parts of the Thunderbolt parsing are adapted from PortScope, as marked in those files.

```
MIT License

Copyright (c) 2026 Alex Zenla

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## WhatPort

- Project: https://github.com/darrylmorley/whatport
- Used for: research into Apple's USB-C port controllers, the `IOPort` registry plane and the SMC per-port power channels. Parts of Bus Stop's IORegistry reading, live monitoring, SMC reading, diagnostics and status item are adapted from WhatPort, as marked in those files.

```
MIT License

Copyright (c) 2025 Darryl Morley

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## WhatCable

- Project: https://github.com/darrylmorley/whatcable
- Used for: research into power telemetry, charger details and attributing devices to Thunderbolt chains. Parts of the USB device tree builder are adapted from WhatCable, as marked in those files. Only the MIT-licensed parts of WhatCable were consulted; its proprietary `Sources/WhatCablePlugins` directory was not used.

```
MIT License

Copyright (c) 2026 Darryl Morley

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

---

## Linux kernel Thunderbolt register definitions

Bus Stop decodes Thunderbolt and USB4 link speed codes (`Current Link Speed`: 0x8 = 10 Gb/s, 0x4 = 20 Gb/s, 0x2 = 40 Gb/s per lane) and link width codes as documented in the Linux kernel's [`drivers/thunderbolt/tb_regs.h`](https://github.com/torvalds/linux/blob/master/drivers/thunderbolt/tb_regs.h). Only these facts about the hardware registers are used. No code from the Linux kernel is copied into Bus Stop, and the kernel's GPL-2.0 licence therefore does not apply to Bus Stop.

---

## Trademarks

Apple, Mac, MacBook, macOS, MagSafe, Xcode and SF Symbols are trademarks of Apple Inc., registered in the U.S. and other countries. Thunderbolt is a trademark of Intel Corporation or its subsidiaries. USB-C, USB4 and USB Type-C are trademarks of the USB Implementers Forum. HDMI is a trademark of HDMI Licensing Administrator, Inc. ViewPorts is the name of a product of its respective developer. All other names are the property of their owners.

Bus Stop is an independent open-source project. It is not affiliated with, sponsored by or endorsed by Apple Inc. or any of the companies named above. Product names are used only to describe compatibility.
