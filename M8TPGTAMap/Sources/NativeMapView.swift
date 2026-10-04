import SwiftUI
import UIKit
import CoreImage

struct MapFocus: Equatable {
    let token = UUID()
    let marker: MapMarker?
    var fitAll: Bool = false
}

@MainActor
struct NativeMapView: UIViewRepresentable {
    let image: UIImage
    let markers: [MapMarker]
    let categories: [MapCategory]
    let completed: Set<String>
    let focus: MapFocus
    let route: [MapMarker]
    let tone: String
    let onSelect: (MapMarker) -> Void
    let onCluster: ([MapMarker]) -> Void
    let onAdd: (Double, Double) -> Void

    func makeUIView(context: Context) -> MapSurface { MapSurface() }
    func updateUIView(_ view: MapSurface, context: Context) {
        view.onSelect = onSelect; view.onCluster = onCluster; view.onAdd = onAdd
        view.update(image: image, markers: markers, categories: categories,
                    completed: completed, focus: focus, route: route, tone: tone)
    }
}

@MainActor
final class MapSurface: UIView, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private let canvas = UIView()
    private let imageView = UIImageView()
    private var markers: [MapMarker] = []
    private var categoryColors: [String: UIColor] = [:]
    private var completed: Set<String> = []
    private var lastBounds = CGSize.zero
    private var lastFocus: UUID?
    private var pendingFocus: MapFocus?
    private var buttons: [UIButton] = []
    private var renderScheduled = false
    private let routeLayer = CAShapeLayer()
    private var route: [MapMarker] = []
    private var originalImage: UIImage?
    private var lastTone = ""
    private let imageContext = CIContext()
    var onSelect: ((MapMarker) -> Void)?
    var onCluster: (([MapMarker]) -> Void)?
    var onAdd: ((Double, Double) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.04, green: 0.06, blue: 0.07, alpha: 1)
        scroll.delegate = self
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.bouncesZoom = true
        scroll.decelerationRate = .fast
        scroll.addSubview(canvas); canvas.addSubview(imageView); addSubview(scroll)
        routeLayer.fillColor = UIColor.clear.cgColor
        routeLayer.strokeColor = UIColor(red: 0.72, green: 0.97, blue: 0.43, alpha: 1).cgColor
        routeLayer.lineJoin = .round; routeLayer.lineCap = .round
        canvas.layer.addSublayer(routeLayer)
        imageView.contentMode = .scaleToFill
        scroll.accessibilityLabel = "Interactive GTA map. Pinch to zoom, drag to pan, long press to add a pin."
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(addPin(_:)))
        scroll.addGestureRecognizer(longPress)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(zoomAt(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(image: UIImage, markers: [MapMarker], categories: [MapCategory],
                completed: Set<String>, focus: MapFocus, route: [MapMarker], tone: String) {
        let imageChanged = originalImage !== image
        if imageChanged {
            scroll.setZoomScale(1, animated: false)
            originalImage = image
            canvas.frame = CGRect(origin: .zero, size: image.size)
            imageView.frame = canvas.bounds
            scroll.contentSize = image.size
            lastBounds = .zero
            setNeedsLayout()
        }
        if imageChanged || tone != lastTone { imageView.image = toned(image, tone: tone); lastTone = tone }
        self.route = route
        self.markers = markers; self.completed = completed
        categoryColors = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, UIColor(Color(hex: $0.color))) })
        if lastFocus != focus.token { pendingFocus = focus; setNeedsLayout() }
        scheduleRender()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        guard bounds.width > 0, bounds.height > 0, let image = imageView.image else { return }
        if bounds.size != lastBounds {
            let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
            scroll.minimumZoomScale = fit
            scroll.maximumZoomScale = max(fit * 24, 2)
            let cover = max(bounds.width / image.size.width, bounds.height / image.size.height)
            scroll.setZoomScale(cover, animated: false)
            lastBounds = bounds.size
            centerCanvas()
        }
        if let focus = pendingFocus {
            pendingFocus = nil; lastFocus = focus.token
            if let marker = focus.marker {
                zoom(to: CGPoint(x: marker.x * Double(image.size.width),
                                 y: marker.y * Double(image.size.height)),
                     scale: min(scroll.maximumZoomScale, scroll.minimumZoomScale * 5), animated: true)
            } else {
                if focus.fitAll { scroll.setZoomScale(scroll.minimumZoomScale, animated: true) }
                else {
                    let cover = max(bounds.width / image.size.width, bounds.height / image.size.height)
                    zoom(to: CGPoint(x: image.size.width * 0.5, y: image.size.height * 0.68), scale: cover, animated: false)
                }
            }
        }
        scheduleRender()
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerCanvas(); scheduleRender() }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { scheduleRender() }
    private func centerCanvas() {
        let insetX = max(0, (scroll.bounds.width - scroll.contentSize.width) / 2)
        let insetY = max(0, (scroll.bounds.height - scroll.contentSize.height) / 2)
        scroll.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }
    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renderScheduled = false; self.renderAnnotations()
        }
    }
    private func renderAnnotations() {
        buttons.forEach { $0.removeFromSuperview() }; buttons.removeAll(keepingCapacity: true)
        guard let image = imageView.image, scroll.zoomScale > 0 else { return }
        let path = UIBezierPath()
        for (index, marker) in route.enumerated() {
            let point = CGPoint(x: marker.x * Double(image.size.width), y: marker.y * Double(image.size.height))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        routeLayer.path = path.cgPath; routeLayer.lineWidth = 3 / scroll.zoomScale
        let visible = canvas.convert(scroll.bounds, from: scroll).insetBy(dx: -40 / scroll.zoomScale,
                                                                          dy: -40 / scroll.zoomScale)
        let cell = 48 / scroll.zoomScale
        var groups: [String: [MapMarker]] = [:]
        for marker in markers {
            let point = CGPoint(x: marker.x * Double(image.size.width), y: marker.y * Double(image.size.height))
            guard visible.contains(point) else { continue }
            let key = "\(Int(point.x / cell)):\(Int(point.y / cell))"
            groups[key, default: []].append(marker)
        }
        for key in groups.keys.sorted() {
            guard let group = groups[key], let first = group.first else { continue }
            let x = group.reduce(0) { $0 + $1.x } / Double(group.count)
            let y = group.reduce(0) { $0 + $1.y } / Double(group.count)
            let button = UIButton(type: .system)
            button.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
            button.center = CGPoint(x: x * Double(image.size.width), y: y * Double(image.size.height))
            button.transform = CGAffineTransform(scaleX: 1 / scroll.zoomScale, y: 1 / scroll.zoomScale)
            button.layer.cornerRadius = 16
            button.layer.borderWidth = 2
            button.layer.borderColor = UIColor.black.withAlphaComponent(0.5).cgColor
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.45; button.layer.shadowRadius = 4
            button.backgroundColor = categoryColors[first.categoryID] ?? .systemGreen
            button.tintColor = .black
            let isDone = group.allSatisfy { completed.contains($0.id) }
            if group.count > 1 {
                button.setTitle("\(group.count)", for: .normal)
                button.setTitleColor(.black, for: .normal)
                button.titleLabel?.font = .boldSystemFont(ofSize: 13)
                button.accessibilityLabel = "\(group.count) nearby locations"
            } else if let index = route.firstIndex(where: { $0.id == first.id }) {
                button.setTitle("\(index + 1)", for: .normal)
                button.setTitleColor(.black, for: .normal)
                button.titleLabel?.font = .boldSystemFont(ofSize: 13)
                button.accessibilityLabel = "Route stop \(index + 1), \(first.title)"
            } else {
                button.setImage(UIImage(systemName: isDone ? "checkmark" : "mappin"), for: .normal)
                button.accessibilityLabel = "\(first.title)\(isDone ? ", collected" : "")"
            }
            button.alpha = isDone ? 0.55 : 1
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                if group.count == 1 { self.onSelect?(first) }
                else { self.onCluster?(group) }
            }, for: .touchUpInside)
            canvas.addSubview(button); buttons.append(button)
        }
    }
    @objc private func addPin(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let image = imageView.image else { return }
        let point = gesture.location(in: canvas)
        guard canvas.bounds.contains(point) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onAdd?(Double(point.x / image.size.width), Double(point.y / image.size.height))
    }
    @objc private func zoomAt(_ gesture: UITapGestureRecognizer) {
        zoom(to: gesture.location(in: canvas),
             scale: min(scroll.maximumZoomScale, scroll.zoomScale * 2), animated: true)
    }
    private func zoom(to point: CGPoint, scale: CGFloat, animated: Bool) {
        let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
        scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                              width: size.width, height: size.height), animated: animated)
    }
    private func toned(_ image: UIImage, tone: String) -> UIImage {
        guard tone != "satellite", let input = CIImage(image: image),
              let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(tone == "night" ? 0.35 : 0.8, forKey: kCIInputSaturationKey)
        filter.setValue(tone == "night" ? -0.20 : 0.02, forKey: kCIInputBrightnessKey)
        filter.setValue(tone == "night" ? 1.15 : 1.45, forKey: kCIInputContrastKey)
        guard let output = filter.outputImage, let cg = imageContext.createCGImage(output, from: input.extent) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }
}
