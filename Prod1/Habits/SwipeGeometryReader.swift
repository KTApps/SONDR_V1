import SwiftUI

struct SwipeableRow<Content: View>: View {
    let content: () -> Content
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void
    
    @State private var offsetX: CGFloat = 0
    private let swipeThreshold: CGFloat = 180 // The threshold for significant swipe

    var body: some View {
        // Content view with dynamic opacity
        content()
            .opacity(offsetX < 0 ? CGFloat(1) - min(abs(offsetX) / swipeThreshold, 1) : (offsetX > 0 ? CGFloat(1) - min(abs(offsetX) / swipeThreshold, 1) : 1)) // Reduce opacity based on swipe direction
            .offset(x: offsetX)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offsetX = value.translation.width
                    }
                    .onEnded { value in
                        if value.translation.width < -swipeThreshold {
                            // Swipe Left Action
                            onSwipeLeft()
                            offsetX = -300
                        } else if value.translation.width > swipeThreshold {
                            // Swipe Right Action
                            onSwipeRight()
                            offsetX = 300
                        } else {
                            // Snap back if no significant swipe
                            offsetX = 0
                        }
                    }
            )
            .animation(.easeInOut, value: offsetX)
    }
}
