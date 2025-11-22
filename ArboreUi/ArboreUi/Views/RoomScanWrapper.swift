//
//  RoomScanWrapper.swift
//  ArboreUi
//
//  Created on November 22, 2025.
//

import SwiftUI

struct RoomScanWrapper: View {
    @State private var captureController = RoomCaptureController()
    
    var body: some View {
        ScanNewRoomView()
            .environment(captureController)
    }
}
