-- Monitor layout (MAG 341C OLED)
-- sdr_min_luminance 0 keeps OLED blacks; defaults (0.2) lift them to gray.
-- sdr_max_luminance ~203 is Rec.2408 reference white for SDR-in-HDR.
hl.monitor({
  output = "HDMI-A-2",
  mode = "3440x1440@175",
  position = "0x0",
  scale = 1,
  bitdepth = 10,
  cm = "hdr",
  sdr_min_luminance = 0,
  sdr_max_luminance = 203,
  sdrbrightness = 1.0,
  sdrsaturation = 0.98,
})

-- NVIDIA driver versions can expose the same physical port as HDMI-A-1.
hl.monitor({
  output = "HDMI-A-1",
  mode = "3440x1440@175",
  position = "0x0",
  scale = 1,
  bitdepth = 10,
  cm = "hdr",
  sdr_min_luminance = 0,
  sdr_max_luminance = 203,
  sdrbrightness = 1.0,
  sdrsaturation = 0.98,
})
