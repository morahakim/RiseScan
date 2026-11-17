//
//  ScanPreviewService.swift
//  RiseScan
//
//  Created by mora hakim on 14/11/26.
//

import Foundation
import ModelIO
import RealityKit
import UIKit

final class ScanPreviewService {

    func loadModel(from folderURL: URL? = nil) throws -> MDLAsset {
        let objURL: URL

        if let folderURL {
            objURL = folderURL.appendingPathComponent(
                "Engineering_iOS_Assessment.obj"
            )
        } else {
            guard let bundleURL = Bundle.main.url(
                forResource: "Engineering_iOS_Assessment",
                withExtension: "obj"
            ) else {
                throw CocoaError(.fileNoSuchFile)
            }

            objURL = bundleURL
        }

        // Check file size.
        let attributes = try FileManager.default.attributesOfItem(
            atPath: objURL.path
        )
        let fileSize = attributes[.size] as? Int64 ?? 0

        // Measure MDLAsset initialization.
        let initStart = Date()
        let asset = MDLAsset(url: objURL)

        // Measure asset parsing/access.
        let countStart = Date()
        let objectCount = asset.count

        guard objectCount > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return asset
    }
    
    func inspectMesh() throws {
        let asset = try loadModel()

        guard let mesh = asset.object(at: 0) as? MDLMesh,
              let submesh = mesh.submeshes?.firstObject as? MDLSubmesh else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let position = mesh.vertexAttributeData(
            forAttributeNamed: MDLVertexAttributePosition
        )

        let texture = mesh.vertexAttributeData(
            forAttributeNamed: MDLVertexAttributeTextureCoordinate
        )

    }
    
    func readVertexData() throws {
        let asset = try loadModel()

        guard let mesh = asset.object(at: 0) as? MDLMesh else {
            throw CocoaError(.fileReadCorruptFile)
        }

        guard let positionData = mesh.vertexAttributeData(
            forAttributeNamed: MDLVertexAttributePosition
        ), let textureData = mesh.vertexAttributeData(
            forAttributeNamed: MDLVertexAttributeTextureCoordinate
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let positionBuffer = positionData.dataStart
        let textureBuffer = textureData.dataStart

        var positions: [SIMD3<Float>] = []
        var textureCoordinates: [SIMD2<Float>] = []

        for index in 0..<mesh.vertexCount {
            let position = positionBuffer
                .advanced(by: index * positionData.stride)
                .assumingMemoryBound(to: SIMD3<Float>.self)
                .pointee

            let texture = textureBuffer
                .advanced(by: index * textureData.stride)
                .assumingMemoryBound(to: SIMD2<Float>.self)
                .pointee

            positions.append(position)
            textureCoordinates.append(texture)
        }
    }
    
    func readIndices() throws {
        let asset = try loadModel()

        guard let mesh = asset.object(at: 0) as? MDLMesh,
              let submesh = mesh.submeshes?.firstObject as? MDLSubmesh else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let indexBuffer = submesh.indexBuffer
        let indexCount = submesh.indexCount

        let indices = indexBuffer.map().bytes
            .assumingMemoryBound(to: UInt32.self)

        for index in 0..<9 {
            print(indices[index])
        }
    }
    
    
    func makeMeshResource(from folderURL: URL? = nil) throws -> MeshResource {
        let totalStart = Date()

        // Load OBJ model.
        let loadStart = Date()
        let asset = try loadModel(from: folderURL)
        print("ModelIO loading time:", Date().timeIntervalSince(loadStart))

        guard let mesh = asset.object(at: 0) as? MDLMesh,
              let submesh = mesh.submeshes?.firstObject as? MDLSubmesh else {
            throw CocoaError(.fileReadCorruptFile)
        }

        // Read vertex attributes.
        let attributeStart = Date()

        guard let positionData = mesh.vertexAttributeData(
            forAttributeNamed: MDLVertexAttributePosition
        ), let textureData = mesh.vertexAttributeData(
            forAttributeNamed: MDLVertexAttributeTextureCoordinate
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        // Read vertex positions and texture coordinates.
        let vertexStart = Date()

        let positionBuffer = positionData.dataStart
        let positions: [SIMD3<Float>] = (0..<mesh.vertexCount).map { index in
            let pointer = positionBuffer
                .advanced(by: index * positionData.stride)
                .assumingMemoryBound(to: SIMD3<Float>.self)

            return pointer.pointee
        }

        let textureBuffer = textureData.dataStart
        let textureCoordinates: [SIMD2<Float>] = (0..<mesh.vertexCount).map { index in
            let pointer = textureBuffer
                .advanced(by: index * textureData.stride)
                .assumingMemoryBound(to: SIMD2<Float>.self)

            return pointer.pointee
        }

        print("Vertex reading time:", Date().timeIntervalSince(vertexStart))

        // Read triangle indices.
        let indexStart = Date()

        guard submesh.indexType.rawValue == 32 else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let indexBuffer = submesh.indexBuffer.map().bytes
            .assumingMemoryBound(to: UInt32.self)

        let indices = Array(
            UnsafeBufferPointer(
                start: indexBuffer,
                count: submesh.indexCount
            )
        )

        print("Index reading time:", Date().timeIntervalSince(indexStart))

        // Build RealityKit mesh.
        var descriptor = MeshDescriptor(name: "ScanMesh")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(
            textureCoordinates
        )
        descriptor.primitives = .triangles(indices)

        let generateStart = Date()
        let resource = try MeshResource.generate(from: [descriptor])

        return resource
    }

    
    
    @MainActor
    func makeTexturedModelEntity(
        from folderURL: URL? = nil
    ) async throws -> ModelEntity {

        let startTime = Date()

        print("Loading mesh started")

        let mesh = try makeMeshResource(from: folderURL)

        print(
            "Mesh creation finished:",
            Date().timeIntervalSince(startTime),
            "seconds"
        )

        let textureStart = Date()

        let textureURL: URL

        if let folderURL {
            textureURL = folderURL.appendingPathComponent(
                "Engineering_iOS_Assessment.jpg"
            )
        } else {
            guard let bundleURL = Bundle.main.url(
                forResource: "Engineering_iOS_Assessment",
                withExtension: "jpg"
            ) else {
                throw CocoaError(.fileNoSuchFile)
            }

            textureURL = bundleURL
        }

        guard let image = UIImage(contentsOfFile: textureURL.path),
              let cgImage = image.cgImage else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let texture = try await TextureResource.generate(
            from: cgImage,
            options: .init(semantic: .color)
        )

        print(
            "Texture creation finished:",
            Date().timeIntervalSince(textureStart),
            "seconds"
        )

        var material = SimpleMaterial()
        material.color = .init(
            tint: .white,
            texture: .init(texture)
        )

        let entity = ModelEntity(
            mesh: mesh,
            materials: [material]
        )

        print(
            "Total model creation:",
            Date().timeIntervalSince(startTime),
            "seconds"
        )

        return entity
    }

    @MainActor
    func savePreview(_ image: UIImage) throws -> URL {
        let maxDimension: CGFloat = 1024

        let imageSize = image.size
        let scale = min(
            1,
            maxDimension / max(imageSize.width, imageSize.height)
        )

        let targetSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)

        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let data = resizedImage.jpegData(compressionQuality: 0.7) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let folder = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        let previewURL = folder.appendingPathComponent("scan-preview.jpg")

        try data.write(to: previewURL, options: .atomic)

        return previewURL
    }

}
