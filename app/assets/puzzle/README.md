# Textures for the piece in the hand (docs/51 §9a)

Optional. Every file that is here is used; every file that is missing is drawn by the shader
(`shaders/tile.frag`) itself. Nothing else needs to change: drop the files in and rebuild.

| File | Size | What |
|---|---|---|
| `matcap_minute.png` | 512 × 512 | Matcap for a minute piece: matte cardboard |
| `matcap_quarter.png` | 512 × 512 | Matcap for a quarter-of-an-hour piece: ink under clear lacquer |
| `matcap_hour.png` | 512 × 512 | Matcap for an hour piece: red enamel |
| `cardboard_normal.png` | 1024 × 1024 | Tileable tangent-space normal map of the cardboard (OpenGL convention, green up) |

A matcap is a lit sphere on a square: the shader looks up the colour for each point of the piece
by its surface normal. Render it on a neutral (mid-grey) background; only the disc is read.
