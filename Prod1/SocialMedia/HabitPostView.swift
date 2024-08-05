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
                
                if viewModel.selectedImage != nil {
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: viewModel.selectedImage!)
                            .resizable()
                            .scaledToFill()
                            .frame(maxHeight: 370)
                            .frame(maxWidth: 395)
                            .clipped()
                            .cornerRadius(10)
                        //            MARK: HABIT ARRAY
                        VStack {
                            ForEach(viewModel.habitDataForDay[viewModel.currentDayOfWeek]?.habitIdArray ?? [], id: \.self) { habit in
                                Text(viewModel.habitDataForDay[viewModel.currentDayOfWeek]?.habitIdName[habit] ?? "")
                                    .overlay(
                                        viewModel.habitDataForDay[viewModel.currentDayOfWeek]?.isHabitStriked[habit] ?? false ?
                                        Rectangle()
                                            .frame(height: 3)
                                            .colorInvert()
                                            .padding(.horizontal, -10)
                                        : nil
                                    )
                            }
                        }
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(5)
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
                            viewModel.uploadPhoto()
                            viewModel.isPostBlurViewVisible = false
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

