//
//  CreateButton.swift
//  SuperSimpleObjectCapture
//  Created by Hugo Rath on 20/03/2025.
//

import SwiftUI
import RealityKit

@MainActor
struct CreateButton: View {
    let session: ObjectCaptureSession
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            Button(action: {
                performAction()
            }, label: {
                Text(label)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.tint)
                    .clipShape(Capsule())
            })

            Button(action: {
                goBack()
            }, label: {
                Text("Back")
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.gray)
                    .clipShape(Capsule())
            })
            .padding(.top, 10)
        }
    }

    private var label: LocalizedStringKey {
        if session.state == .ready {
            return "démarrer la détection"
        } else if session.state == .detecting {
            return "démarrer la détection"
        } else {
            return "Undefined"
        }
    }

    private func performAction() {
        if session.state == .ready {
            let isDetecting = session.startDetecting()
            print(isDetecting ? "▶️Start detecting" : "😨Not start detecting")
        } else if session.state == .detecting {
            session.startCapturing()
        } else {
            print("Undefined")
        }
    }

    private func goBack() {
        presentationMode.wrappedValue.dismiss()
    }
}
