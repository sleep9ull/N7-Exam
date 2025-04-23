//
//  SMBLoginView.swift
//  N7-Exam
//
//  Created by 斯利普固 on 2025/4/21.
//

import SwiftUI

struct SMBLoginView: View {
    @ObservedObject var viewModel: SMBViewModel
    @State private var isFocused: Bool = false
    @State private var isLoggingIn: Bool = false
    @State private var showPassword: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Server")) {
                    TextField("server", text: $viewModel.serverAddress)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                    
                    TextField("share", text: $viewModel.shareName)
                        .autocapitalization(.none)
                }
                
                Section(header: Text("Login")) {
                    TextField("username (optional)", text: $viewModel.username)
                        .autocapitalization(.none)
                        .textContentType(.username)
                    
                    HStack {
                        if showPassword {
                            TextField("password", text: $viewModel.password)
                                .textContentType(.password)
                        } else {
                            SecureField("password (optional)", text: $viewModel.password)
                                .textContentType(.password)
                        }
                        
                        Button(action: {
                            showPassword.toggle()
                        }) {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        loginToSMB()
                    }) {
                        if isLoggingIn {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .bold()
                        }
                    }
                    .disabled(isLoggingIn || !isFormValid)
                }
                
                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
                
                // 示例连接 Section
                Section(header: Text("Example")) {
                    Button("example") {
                        viewModel.serverAddress = "smb://192.168.31.250"
                        viewModel.shareName = "smb"
                        viewModel.username = "jinchunxu"
                        viewModel.password = "kl;'"
                    }
                }
            }
            .navigationTitle("SMB Login")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var isFormValid: Bool {
        !viewModel.serverAddress.isEmpty &&
        !viewModel.shareName.isEmpty &&
        !viewModel.username.isEmpty &&
        !viewModel.password.isEmpty
    }
    
    private func loginToSMB() {
        isLoggingIn = true
        
        Task {
            let success = await viewModel.connect()
            
            await MainActor.run {
                isLoggingIn = false
                // 成功连接后不需要执行其他操作
                // viewModel.isConnected 状态会在 ViewModel 中自动更新
            }
        }
    }
}

struct SMBLoginView_Previews: PreviewProvider {
    static var previews: some View {
        SMBLoginView(
            viewModel: SMBViewModel()
        )
    }
}
