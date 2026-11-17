//
//  ScanPreviewView.swift
//  RiseScan
//
//  Created by mora hakim on 15/11/26.
//

import SwiftUI
import RealityKit

struct ScanPreviewView: UIViewRepresentable {

    var modelFolderURL: URL? = nil
    var onPreviewCreated: ((UIImage) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(
            frame: .zero,
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )

        context.coordinator.modelFolderURL = modelFolderURL

        loadModel(
            into: arView,
            from: modelFolderURL,
            createPreview: modelFolderURL == nil
        )

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        guard context.coordinator.modelFolderURL != modelFolderURL else {
            return
        }

        context.coordinator.modelFolderURL = modelFolderURL

        loadModel(
            into: uiView,
            from: modelFolderURL,
            createPreview: false
        )
    }

    private func loadModel(
        into arView: ARView,
        from folderURL: URL?,
        createPreview: Bool
    ) {
        Task { @MainActor in
            let startTime = Date()

            do {
                let entity = try await ScanPreviewService()
                    .makeTexturedModelEntity(from: folderURL)

                let bounds = entity.visualBounds(relativeTo: nil)
                let center = bounds.center
                let extents = bounds.extents

                let maxDimension = max(
                    extents.x,
                    max(extents.y, extents.z)
                )

                guard maxDimension > 0 else {
                    return
                }

                let scale = 1.5 / maxDimension

                entity.scale = SIMD3<Float>(repeating: scale)

                entity.transform.rotation = simd_quatf(
                    angle: .pi / 2,
                    axis: SIMD3<Float>(0, 1, 0)
                )

                entity.position = SIMD3<Float>(
                    -center.x * scale,
                    -center.y * scale,
                    -center.z * scale - 2.0
                )

                // Collision tidak dibuat untuk mengurangi waktu loading.
                let anchor = AnchorEntity(world: .zero)
                anchor.addChild(entity)

                arView.scene.anchors.removeAll()
                arView.scene.addAnchor(anchor)

                guard createPreview else {
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    arView.snapshot(saveToHDR: false) { image in
                        guard let image else {
                            print("Snapshot failed")
                            return
                        }

                        onPreviewCreated?(image)
                    }
                }

            } catch {
                print("Model display failed:", error)
            }
        }
    }

    final class Coordinator {
        var modelFolderURL: URL?
    }
}

