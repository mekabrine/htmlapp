import UIKit
import MapKit
import WebKit

@MainActor
final class HTMLAppEmbeddedMap: NSObject, MKMapViewDelegate {
    private weak var webView: WKWebView?
    private var map: MKMapView?
    private var leading: NSLayoutConstraint?
    private var top: NSLayoutConstraint?
    private var width: NSLayoutConstraint?
    private var height: NSLayoutConstraint?
    private var ids: [ObjectIdentifier: String] = [:]
    init(webView: WKWebView) { self.webView = webView }
    func hide() { map?.removeFromSuperview(); map = nil; ids = [:] }
    func show(_ args: [String: Any]) throws {
        guard let webView, let host = webView.superview,
              let frame = args["frame"] as? [String: Any],
              let x = frame["x"] as? Double, let y = frame["y"] as? Double,
              let w = frame["width"] as? Double, let h = frame["height"] as? Double,
              [x,y,w,h].allSatisfy({ $0.isFinite }), x >= 0, y >= 0, w >= 44, h >= 44,
              x + w <= Double(webView.bounds.width) + 1,
              y + h <= Double(webView.bounds.height) + 1 else { throw Failure.invalid }
        let view: MKMapView
        if let map { view = map }
        else {
            view = MKMapView(); view.delegate = self; view.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(view); map = view
            leading = view.leadingAnchor.constraint(equalTo: webView.leadingAnchor)
            top = view.topAnchor.constraint(equalTo: webView.topAnchor)
            width = view.widthAnchor.constraint(equalToConstant: w)
            height = view.heightAnchor.constraint(equalToConstant: h)
            NSLayoutConstraint.activate([leading!, top!, width!, height!])
        }
        leading?.constant = x; top?.constant = y; width?.constant = w; height?.constant = h
        if let center = coordinate(args["center"]) {
            let raw = (args["span"] as? NSNumber)?.doubleValue ?? 0.05
            guard raw.isFinite else { throw Failure.invalid }
            let span = min(180, max(0.001, raw))
            view.setRegion(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)), animated: false)
        }
        if let annotations = args["annotations"] as? [[String: Any]] {
            guard annotations.count <= 200 else { throw Failure.invalid }
            view.removeAnnotations(view.annotations); ids = [:]
            for item in annotations {
                guard let point = coordinate(item), let id = item["id"] as? String, id.count <= 80 else { throw Failure.invalid }
                let annotation = MKPointAnnotation(); annotation.coordinate = point
                annotation.title = String((item["title"] as? String ?? "").prefix(100))
                annotation.subtitle = String((item["subtitle"] as? String ?? "").prefix(180))
                ids[ObjectIdentifier(annotation)] = id; view.addAnnotation(annotation)
            }
        }
        if let routes = args["routes"] as? [[[String: Any]]] {
            guard routes.count <= 10 else { throw Failure.invalid }
            view.removeOverlays(view.overlays)
            for route in routes {
                guard route.count <= 2000 else { throw Failure.invalid }
                var points = route.compactMap { coordinate($0) }
                guard points.count == route.count, points.count >= 2 else { throw Failure.invalid }
                view.addOverlay(MKPolyline(coordinates: &points, count: points.count))
            }
        }
    }
    private func coordinate(_ value: Any?) -> CLLocationCoordinate2D? {
        guard let point = value as? [String: Any], let lat = point["latitude"] as? Double,
              let lon = point["longitude"] as? Double, lat.isFinite, lon.isFinite,
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
        let renderer = MKPolylineRenderer(polyline: line); renderer.strokeColor = .systemBlue; renderer.lineWidth = 4
        return renderer
    }
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let annotation = view.annotation, let id = ids[ObjectIdentifier(annotation)],
              let bytes = try? JSONSerialization.data(withJSONObject: ["id": id]),
              let json = String(data: bytes, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('htmlapp:map-select',{detail:\(json)}));")
    }
    enum Failure: LocalizedError { case invalid
        var errorDescription: String? { "Provide a visible map frame, valid coordinates, <=200 annotations and <=10 routes of <=2000 points." }
    }
}
