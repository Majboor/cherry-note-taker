import Cocoa
import WebKit

// Offscreen snapshotter: renders the REAL app UI (htmlTemplate from html.swift) with sanitized
// sample data and saves a retina PNG. Usage: snap <preset> <out.png>
let A = CommandLine.arguments
let preset = A.count > 1 ? A[1] : "clips"
let outPath = A.count > 2 ? A[2] : "out.png"

func jstr(_ o: Any) -> String { String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)! }

func gradientThumb() -> String {
    let w = 240, h = 150
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let g = NSGradient(colors: [NSColor(calibratedRed: 0.23, green: 0.51, blue: 1, alpha: 1),
                                NSColor(calibratedRed: 0.13, green: 0.83, blue: 0.83, alpha: 1)])!
    g.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 35)
    NSGraphicsContext.restoreGraphicsState()
    return "data:image/png;base64," + rep.representation(using: .png, properties: [:])!.base64EncodedString()
}

let NOW = Date().timeIntervalSince1970
let DAY = 86400.0

func notes() -> [[String: Any]] {
    return [
      ["name":"welcome","title":"Welcome","category":"General","tags":["start","howto"],"body":"# Welcome\n\n**Cherry** keeps your handovers, commands and checklists one click away — in the menu bar and in Spotlight.\n\n## Try it\n- Click **+** to add a note\n- Filter by **category**, or search titles, tags & text\n- ⌘-Space → type a note's name to jump straight to it"],
      ["name":"llm-keys","title":"LLM API keys","category":"AI & LLM","tags":["groq","openai","openrouter"],"body":"# LLM API keys\n\n## Groq\n- Base: `https://api.groq.com/openai/v1`\n- Fast + cheap — default for chat\n\n## OpenAI\n- Base: `https://api.openai.com/v1`"],
      ["name":"model-routing","title":"Model routing","category":"AI & LLM","tags":["priority","codex","claude"],"body":"# Model routing\n\n1. Local CLIs first\n2. Proxy endpoint\n3. Other providers"],
      ["name":"posting","title":"Posting webhooks","category":"Social & Posting","tags":["make.com","linkedin","reddit"],"body":"# Posting webhooks\n\nPOST JSON with an `action` field to the webhook to publish to a channel."],
      ["name":"deploy","title":"Deploy","category":"Infra & Data","tags":["build","release"],"body":"# Deploy\n\n## Steps\n1. Pull latest\n2. Build & sign\n3. Tag the release\n\n```bash\ngit pull --rebase\n./Scripts/build.sh\n```"],
      ["name":"cli-flags","title":"CLI flags","category":"Reference","tags":["cli","cheatsheet"],"body":"# CLI flags\n\n- `-p` print / non-interactive\n- `--resume <id>` resume a session"],
      ["name":"vps","title":"VPS & SSH","category":"Servers & SSH","tags":["ssh","vps"],"body":"# VPS & SSH\n\n`ssh root@host` — main box that runs the services."],
      ["name":"standup","title":"Standup","category":"General","tags":["notes"],"body":"# Standup\n\n- Shipped category filter + note search\n- Reviewing PR #42\n- Next: standalone editor window"]
    ]
}

func clips() -> [[String: Any]] {
    var c: [[String: Any]] = []
    func add(_ o: [String: Any], _ ago: Double) { var x = o; x["ts"] = NOW - ago; x["id"] = "c\(c.count)"; c.append(x) }
    add(["kind":"link","preview":"https://github.com/Majboor/cherry-note-taker","len":36,"count":4], 60)
    add(["kind":"error","preview":"TypeError: Cannot read properties of undefined (reading 'map')\n    at render (App.jsx:42)\n    at renderWithHooks (react-dom.js:14985)","len":150,"fav":true], 400)
    add(["kind":"code","lang":"swift","preview":"func greet(_ name: String) -> String {\n    return \"Hi \\(name)\"\n}","len":64], 900)
    add(["kind":"email","preview":"jordan@example.com","len":18], 1500)
    add(["kind":"color","preview":"#3b82f6","len":7], 2400)
    add(["kind":"image","name":"Screenshot.png","thumb":gradientThumb(),"path":"/clips/img.png"], 3600)
    add(["kind":"path","preview":"~/projects/app/src/index.ts","len":27], 5400)
    add(["kind":"ip","preview":"192.168.1.24","len":12], DAY + 200)
    add(["kind":"phone","preview":"+1 (415) 555-0142","len":17], DAY + 3000)
    add(["kind":"file","name":"design-spec.pdf","path":"~/Downloads/design-spec.pdf"], DAY + 6000)
    add(["kind":"text","preview":"remember to email the team about the launch","len":43], DAY + 9000)
    return c
}

// preset -> (view, activeIndex, postJS, height)
func spec() -> (String, Int, String, CGFloat) {
    switch preset {
    case "home":   return ("home", 0, "", 560)
    case "find":   return ("home", 0, "noteFilter='AI & LLM';noteSearch='';route();", 470)
    case "note":   return ("note", 1, "", 560)
    case "clips":  return ("clips", 0, "", 680)
    case "search": return ("clips", 0, "clipSearch='error';var q=document.getElementById('clipq');if(q){q.value='error'};renderClipList();", 470)
    case "fav":    return ("clips", 0, "clipFilter='fav';route();", 470)
    case "toast":  return ("clips", 0, "copyClip('c0');", 680)
    default:       return ("clips", 0, "", 680)
    }
}

final class Snapper: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var win: NSWindow!; var web: WKWebView!
    func applicationDidFinishLaunching(_ n: Notification) {
        let size = NSSize(width: 600, height: spec().3)
        let cfg = WKWebViewConfiguration()
        web = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: cfg)
        web.navigationDelegate = self
        win = NSWindow(contentRect: NSRect(x: 40, y: 40, width: size.width, height: size.height),
                       styleMask: .borderless, backing: .buffered, defer: false)
        win.contentView = web; win.alphaValue = 0.0
        win.orderFrontRegardless()
        // The page now boots on a slim index and asks the app for everything else; here we
        // hand it the sample notes (bodies attached, so no fetch) and the sample clips directly.
        let html = htmlTemplate.replacingOccurrences(of: "/*__NOTES__*/", with: jstr(notes()))
        web.loadHTMLString(html, baseURL: nil)
    }
    func webView(_ w: WKWebView, didFinish nav: WKNavigation!) {
        let (view, active, postJS, _) = spec()
        let boot = "__clips(\(jstr(clips())));__screens([]);"
            + (view == "note" ? "__show({view:'home'});openNote(\(active));" : "__show({view:'\(view)'});")
        let run = { (then: @escaping () -> Void) in
            w.evaluateJavaScript(boot + postJS) { _, _ in then() }
        }
        run {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                let cfg = WKSnapshotConfiguration()
                w.takeSnapshot(with: cfg) { img, _ in
                    if let img = img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                       let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: outPath))
                        FileHandle.standardError.write("saved \(outPath) \(rep.pixelsWide)x\(rep.pixelsHigh)\n".data(using: .utf8)!)
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

let app = NSApplication.shared
let d = Snapper(); app.delegate = d
app.setActivationPolicy(.accessory)
app.run()
