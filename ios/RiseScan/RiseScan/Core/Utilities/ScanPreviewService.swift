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

    func loadModel() throws -> MDLAsset {
        guard let objURL = Bundle.main.url(
            forResource: "Engineering_iOS_Assessment",
            withExtension: "obj"
        ) else {
            throw CocoaError(.fileNoSuchFile)
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
    
    
    func makeMeshResource() throws -> MeshResource {
        let asset = try loadModel()

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
    func makeTexturedModelEntity() async throws -> ModelEntity {
        // Create mesh from OBJ.
        let mesh = try makeMeshResource()

        // Find JPG texture.
        guard let textureURL = Bundle.main.url(
            forResource: "Engineering_iOS_Assessment",
            withExtension: "jpg"
        ) else {
            throw CocoaError(.fileNoSuchFile)
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


}
