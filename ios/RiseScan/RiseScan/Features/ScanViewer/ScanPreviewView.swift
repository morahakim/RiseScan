//
//  ScanPreviewView.swift
//  RiseScan
//
//  Created by mora hakim on 15/11/26.
//

import SwiftUI
import RealityKit

struct ScanPreviewView: UIViewRepresentable {
    
    var onPreviewCreated: ((UIImage) -> Void)? = nil

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(
            frame: .zero,
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )

        Task { @MainActor in
            do {
                let entity = try await ScanPreviewService()
                    .makeTexturedModelEntity()

                let bounds = entity.visualBounds(relativeTo: nil)
                let center = bounds.center
                let extents = bounds.extents

                let maxDimension = max(
                    extents.x,
                    max(extents.y, extents.z)
                )

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
                
                entity.generateCollisionShapes(recursive: true)

                let anchor = AnchorEntity(world: .zero)
                anchor.addChild(entity)

                arView.scene.addAnchor(anchor)

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

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

