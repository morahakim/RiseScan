//
//  ContentView.swift
//  RiseScan
//
//  Created by mora hakim on 14/11/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ScanPreviewView { image in
            do {
                let url = try ScanPreviewService().savePreview(image)

                let size = try FileManager.default
                    .attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
            } catch {
                print("Preview save failed:", error)
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
