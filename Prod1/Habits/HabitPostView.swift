//
//  HabitPostView.swift
//  Prod1
//
//  Created by Kelvin Mahaja on 16/07/2024.
//

import SwiftUI
import FirebaseStorage
import FirebaseFirestore

struct HabitPostView: View {
    @EnvironmentObject var viewModel: ViewModel
    
    var body: some View {
        ZStack {
            BlurEffect(style: .systemMaterialDark)
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Button {
                        viewModel.backButton.toggle()
                    } label: {
                        Image(systemName: "multiply")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .padding()
                
                if let user = viewModel.currentUser {
                    HStack {
                        Text(user.initial)
                            .font(.title)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.gray)
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading) {
                            Text(user.username)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            Text("\(viewModel.habitStreak) Day Streak")
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                }
                
                Spacer()
                    .frame(height: 10)
                
                if viewModel.selectedImage != nil {
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: viewModel.selectedImage!)
                            .resizable()
                            .scaledToFill()
                            .frame(maxHeight: .infinity)
                            .frame(maxWidth: 395)
                            .clipped()
                            .cornerRadius(10)
                    }
                }
                
                Spacer()
                    .frame(height: 40)
                
                ZStack {
                    if viewModel.caption.isEmpty {
                        Text("Write your caption")
                            .foregroundColor(.gray)
                            .padding(.trailing, 220)
                    }
                        
                    TextField("", text: $viewModel.caption)
                        .foregroundColor(.primary)
                        .padding()
                }
                
                HStack {
                    Button {
                        viewModel.libraryIsVisible = true
                    } label: {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    .padding()

                    Spacer()
                        .frame(width: 90)
                    
                    if viewModel.selectedImage != nil {
                        Button {
                            Task {
                                await viewModel.uploadPost()
                            }
                            viewModel.isPostBlurViewVisible = false
                            viewModel.isBlurViewVisible = false
                        } label: {
                            Text("POST")
                                .font(.title2)
                                .fontWeight(.black)
                                .foregroundColor(.white)
                        }
                    }
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $viewModel.showImagePicker) {
            withAnimation {
                ImagePicker(image: $viewModel.capturedImage)
            }
        }
        .sheet(isPresented: $viewModel.libraryIsVisible) {
            withAnimation {
                LibraryPicker(libraryIsVisible: $viewModel.libraryIsVisible, selectedImage: $viewModel.selectedImage)
            }
        }
        .sheet(isPresented: $viewModel.backButton) {
            withAnimation {
                List {
                    Section {
                        Button {
                            viewModel.showImagePicker = true
                        } label: {
                            SettingsButton(image: "camera", action: "Retake")
                                .padding(.horizontal, -5)
                        }
                        
                        Button {
                            viewModel.isPostBlurViewVisible = false
                        } label: {
                            SettingsButton(image: "arrowshape.backward", action: "Go Back")
                                .padding(.horizontal, -1)
                        }
                    }
                    .foregroundColor(.black)
                }
                .presentationDetents([.fraction(1/5)])
                .colorInvert()
            }
        }
    }
}

struct HabitPostView_Previews: PreviewProvider {
    static var previews: some View {
        return HabitPostView()
            .environmentObject(MockViewModel() as ViewModel)
    }
}

