// The front of a piece in the hand (docs/51 §9a): the photo on a body that rounds off at its edge
// and catches a light that stays put while the piece turns.
//
// The bevel comes from a height map: the piece's outline filled and blurred once, so it is 1 inside
// and falls to 0 across the edge. Normals are its finite differences. The material follows the
// tier: a minute is a photo printed on matte cardboard, a quarter of an hour sits under clear
// lacquer with an ink lip, an hour has a lip of red enamel with a hard highlight.
//
// Textures are optional (assets/puzzle/README.md): a matcap per tier and a tileable cardboard normal
// map. Without them every material is drawn here.
//
// Coordinates: FlutterFragCoord() is in the tile's own local units (the app checks this once at
// start and draws without the shader where it is not).

#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;       // the tile's box, local units
uniform vec4 uSrc;        // the photo's part of the image, normalised: x, y, w, h
uniform vec3 uLight;      // towards the light, in the tile's frame (x right, y down, z out of the front)
uniform vec3 uView;       // towards the eye, same frame
uniform vec3 uRim;        // the lip's colour: ink for a quarter, red for an hour
uniform float uTier;      // 0 minute, 1 quarter, 2 hour, 3 a whole picture
uniform vec2 uTexel;      // one height-map texel, in uv
uniform float uMatcap;    // 1 when uMatcapTex holds a real matcap
uniform float uNormalMap; // 1 when uNormalTex holds the cardboard normal map
uniform float uProbe;     // 1: write the fragment coordinate instead, for the start-up check

uniform sampler2D uPhoto;
uniform sampler2D uHeight;
uniform sampler2D uMatcapTex;
uniform sampler2D uNormalTex;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  if (uProbe > 0.5) {
    fragColor = vec4(fc.x / 255.0, fc.y / 255.0, 0.0, 1.0);
    return;
  }
  vec2 uv = clamp(fc / uSize, 0.0, 1.0);

  float h = texture(uHeight, uv).r;
  float hx = texture(uHeight, uv + vec2(uTexel.x, 0.0)).r - texture(uHeight, uv - vec2(uTexel.x, 0.0)).r;
  float hy = texture(uHeight, uv + vec2(0.0, uTexel.y)).r - texture(uHeight, uv - vec2(0.0, uTexel.y)).r;
  vec3 n = normalize(vec3(-hx * 3.2, -hy * 3.2, 1.0));

  // Cardboard has a grain: the normal map where there is one, a faint noise where there is not.
  if (uNormalMap > 0.5) {
    vec3 t = texture(uNormalTex, fract(uv * 2.0)).rgb * 2.0 - 1.0;
    n = normalize(n + vec3(t.x, -t.y, 0.0) * 0.12);
  } else {
    vec2 g = floor(fc * 1.5);
    n = normalize(n + vec3(hash(g) - 0.5, hash(g + 17.0) - 0.5, 0.0) * 0.06);
  }

  vec3 photo = texture(uPhoto, uSrc.xy + uv * uSrc.zw).rgb;
  // 1 on the rounded edge, 0 on the flat of the face: a lip of enamel or ink has a crisp inner
  // border, where the shine of the bevel runs out over the photo.
  float bevel = 1.0 - smoothstep(0.5, 0.92, h);
  float lip = 1.0 - smoothstep(0.66, 0.74, h);

  vec3 L = normalize(uLight);
  vec3 V = normalize(uView);
  vec3 H = normalize(L + V);
  float diffuse = max(dot(n, L), 0.0);
  float ndh = max(dot(n, H), 0.0);

  vec3 base = photo;
  float ambient = 0.62;
  float kd = 0.48;
  float ks = 0.05;
  float shine = 10.0;
  if (uTier < 0.5) {
    // A minute: printed on matte card. Soft light, no shine to speak of.
    base *= 0.97 + 0.06 * hash(floor(fc * 0.75));
  } else if (uTier < 1.5) {
    // A quarter of an hour: under clear lacquer, its lip in ink.
    base = mix(base, uRim, lip * 0.8);
    ks = 0.55;
    shine = 70.0;
  } else if (uTier < 2.5) {
    // An hour: red enamel round the edge, hard light on it, and a glossier photo.
    base = mix(base, uRim, lip);
    ks = mix(0.22, 1.1, max(lip, bevel));
    shine = mix(36.0, 90.0, lip);
  } else {
    // A whole finished picture: a print on board, a little satin.
    ks = 0.16;
    shine = 28.0;
  }

  vec3 color = base * (ambient + kd * diffuse) + vec3(ks * pow(ndh, shine));
  if (uMatcap > 0.5) {
    vec3 m = texture(uMatcapTex, vec2(n.x, n.y) * 0.5 + 0.5).rgb;
    color = mix(color, base * m * 1.7, 0.55);
  }
  fragColor = vec4(color, 1.0);
}
