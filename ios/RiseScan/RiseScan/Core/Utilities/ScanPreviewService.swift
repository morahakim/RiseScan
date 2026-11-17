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

        let asset = MDLAsset(url: objURL)

        guard asset.count > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        print("Model loaded successfully")
        print("Object count:", asset.count)

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

        print("Vertex count:", mesh.vertexCount)

        print("Position format:", position?.format.rawValue ?? -1)
        print("Position stride:", position?.stride ?? -1)

        print("Texture format:", texture?.format.rawValue ?? -1)
        print("Texture stride:", texture?.stride ?? -1)

        print("Index count:", submesh.indexCount)
        print("Index type:", submesh.indexType.rawValue)
        print("Geometry type:", submesh.geometryType.rawValue)
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

        print("Positions:", positions.count)
        print("Texture coordinates:", textureCoordinates.count)
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

        print("First 9 indices:")

        for index in 0..<9 {
            print(indices[index])
        }

        print("Total indices:", indexCount)
    }
    
    
    func makeMeshResource(from folderURL: URL? = nil) throws -> MeshResource {
        let asset = try loadModel(from: folderURL)

        guard let mesh = asset.object(at: 0) as? MDLMesh,
              let submesh = mesh.submeshes?.firstObject as? MDLSubmesh else {
            throw CocoaError(.fileReadCorruptFile)
        }

        guard let positionData = mesh.vertexAttributeData(
            forAttributeNamed: MDLVertexAttributePosition
        ), let textureData = mesh.vertexAttributeData(
            forAttributeNamed: MDLVertexAttributeTextureCoordinate
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        // Read vertex positions.
        let positionBuffer = positionData.dataStart
        var positions: [SIMD3<Float>] = []

        for index in 0..<mesh.vertexCount {
            let position = positionBuffer
                .advanced(by: index * positionData.stride)
                .assumingMemoryBound(to: SIMD3<Float>.self)
                .pointee

            positions.append(position)
        }

        // Read texture coordinates.
        let textureBuffer = textureData.dataStart
        var textureCoordinates: [SIMD2<Float>] = []

        for index in 0..<mesh.vertexCount {
            let texture = textureBuffer
                .advanced(by: index * textureData.stride)
                .assumingMemoryBound(to: SIMD2<Float>.self)
                .pointee

            textureCoordinates.append(texture)
        }

        // Read triangle indices.
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

        // Build RealityKit mesh.
        var descriptor = MeshDescriptor(name: "ScanMesh")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(
            textureCoordinates
        )
        descriptor.primitives = .triangles(indices)

        let resource = try MeshResource.generate(from: [descriptor])

        print("RealityKit mesh created successfully")
        print("Position count:", positions.count)
        print("Texture count:", textureCoordinates.count)
        print("Index count:", indices.count)

        return resource
    }
    
    
    @MainActor
    func makeTexturedModelEntity(from folderURL: URL? = nil) async throws -> ModelEntity {
        // Create mesh from OBJ.
        let mesh = try makeMeshResource(from: folderURL)

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

        // Load texture asynchronously.
        guard let image = UIImage(contentsOfFile: textureURL.path),
              let cgImage = image.cgImage else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let texture = try await TextureResource.generate(
            from: cgImage,
            options: .init(semantic: .color)
        )

        // Create material with texture.
        var material = SimpleMaterial()
        material.color = .init(
            tint: .white,
            texture: .init(texture)
        )

        // Combine mesh and material.
        let entity = ModelEntity(
            mesh: mesh,
            materials: [material]
        )

        print("Textured model created successfully")

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
