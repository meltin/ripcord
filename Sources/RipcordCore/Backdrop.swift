import Foundation

/// The panel's optional animated backdrop: a Metal fragment function drawn behind its text. Each
/// shader, built in or in `~/.config/ripcord/shaders`, defines one function,
/// `float4 backdrop(float2 p, Backdrop b)`, with `p` in points from the panel's top-left and a
/// straight sRGB color and alpha back; Ripcord premultiplies it and clips it to the corners.
public enum Backdrop {
  /// What `backdrop` is set to when it draws nothing.
  public static let off = "off"

  /// The built-in shaders' bodies, by the name the setting takes.
  public static let builtIns: [(name: String, body: String)] = [
    ("glow", glow), ("matrix", matrix),
  ]

  /// The full Metal source for a shader's body: the inputs before it, and the functions that
  /// call it after. `#line 1` makes an error's line number the body's own.
  public static func source(body: String) -> String {
    header + "#line 1\n" + body + "\n" + footer
  }

  /// What the setting offers: Off, the built-in shaders, then the `.metal` files in `folder`.
  public static func choices(in folder: URL) -> [String] {
    let files =
      ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
      .filter { $0.hasSuffix(".metal") }
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    return [off] + builtIns.map(\.name) + files
  }

  /// The body `setting` names: a built-in shader's, or the text of a file in `folder`; nil for
  /// Off. Throws when a file can't be read, or is over 32 KB.
  public static func body(for setting: String, in folder: URL) throws -> String? {
    guard setting != off else { return nil }
    if let builtIn = builtIns.first(where: { $0.name == setting }) { return builtIn.body }
    let url = folder.appending(path: setting)
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= 32 * 1024 else { throw TooLarge() }
    return try String(contentsOf: url, encoding: .utf8)
  }

  struct TooLarge: LocalizedError {
    var errorDescription: String? { "A shader can be at most 32 KB." }
  }

  /// Whether to draw one still frame rather than animate: under Reduce Motion, or in Low Power
  /// Mode, as the system asks.
  public static func isStill(reduceMotion: Bool, lowPower: Bool) -> Bool {
    reduceMotion || lowPower
  }

  /// Laid out as Ripcord's Swift side fills it: 16-byte rows, `accent` on its own.
  static let header = """
    #include <metal_stdlib>
    using namespace metal;
    struct Backdrop {
      float2 size;
      float time;
      float dark;
      float4 accent;
      float keystroke;
      float query;
      float field;
      float scale;
    };

    """

  static let footer = """
    struct RipcordVertex { float4 position [[position]]; };

    vertex RipcordVertex ripcord_vertex(uint id [[vertex_id]]) {
      float2 corners[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
      RipcordVertex out;
      out.position = float4(corners[id], 0, 1);
      return out;
    }

    fragment float4 ripcord_fragment(
      RipcordVertex in [[stage_in]], constant Backdrop &b [[buffer(0)]]
    ) {
      float2 p = in.position.xy / b.scale;
      float4 c = backdrop(p, b);
      // The panel's rounded corners, 22 points, smoothed over a pixel.
      float r = 22.0;
      float2 q = abs(p - b.size * 0.5) - (b.size * 0.5 - r);
      float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
      float a = saturate(c.a) * saturate(0.5 - d * b.scale);
      return float4(saturate(c.rgb) * a, a);
    }
    """

  /// The accent color welling up from the bottom, brighter for a moment after each keystroke.
  static let glow = """
    float4 backdrop(float2 p, Backdrop b) {
      float2 uv = p / b.size;
      float wave = 0.5 + 0.5 * sin(uv.x * 6.0 + b.time * 0.6);
      float rise = smoothstep(0.35, 1.0, uv.y + 0.08 * wave);
      float pulse = exp(-b.keystroke * 3.0);
      float strength = mix(0.22, 0.4, b.dark) * (0.7 + 0.3 * pulse);
      return float4(b.accent.rgb, rise * strength);
    }
    """

  /// Columns of blocky glyphs raining down, quicker and brighter as you type.
  static let matrix = """
    float ripcord_hash(float2 v) {
      return fract(sin(dot(v, float2(12.9898, 78.233))) * 43758.5453);
    }

    float4 backdrop(float2 p, Backdrop b) {
      float cell = 14.0;
      float2 grid = floor(p / cell);
      float2 inner = fract(p / cell);
      float speed = 4.0 + 6.0 * ripcord_hash(float2(grid.x, 1.0));
      float lift = 1.0 + 1.5 * exp(-b.keystroke * 2.0);
      float head = fmod(b.time * speed * lift + ripcord_hash(float2(grid.x, 7.0)) * 60.0, 60.0);
      float behind = head - grid.y;
      float trail = behind >= 0.0 ? exp(-behind * 0.25) : 0.0;
      // A glyph: a 3×5 grid of dots, changing now and then.
      float2 pixel = floor(inner * float2(3.0, 5.0));
      float change = floor(b.time * 2.0 + ripcord_hash(grid) * 10.0);
      float lit = step(0.45, ripcord_hash(grid * 3.1 + pixel + change));
      float inside = step(0.12, inner.x) * step(inner.x, 0.88) * step(0.08, inner.y)
        * step(inner.y, 0.92);
      float3 green = mix(float3(0.0, 0.45, 0.15), float3(0.0, 0.85, 0.35), b.dark);
      float3 color = mix(green, float3(0.75, 1.0, 0.8), step(behind, 0.5));
      float a = trail * lit * inside * mix(0.35, 0.55, b.dark);
      return float4(color, a);
    }
    """
}
