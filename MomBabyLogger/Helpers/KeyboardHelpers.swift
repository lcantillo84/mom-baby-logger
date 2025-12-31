//
//  KeyboardHelpers.swift
//  MomBabyLogger
//
//  Keyboard dismissal utilities for the app
//

import SwiftUI

// MARK: - Focus Field Enum
/// Generic focus field enum that can be used across views
enum FocusField: Hashable {
    case amount
    case notes
}

// MARK: - Keyboard Dismiss Gesture
/// View modifier that adds tap-to-dismiss functionality
struct DismissKeyboardOnTap: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
    }
}

// MARK: - Keyboard Toolbar
/// View modifier that adds a Done button above the keyboard
struct KeyboardToolbar: ViewModifier {
    @FocusState.Binding var focusedField: FocusField?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                    .fontWeight(.semibold)
                }
            }
    }
}

// MARK: - View Extensions
extension View {
    /// Adds tap-to-dismiss keyboard functionality to any view
    func dismissKeyboardOnTap() -> some View {
        modifier(DismissKeyboardOnTap())
    }

    /// Adds a Done button toolbar above the keyboard
    func keyboardDoneButton(focusedField: FocusState<FocusField?>.Binding) -> some View {
        modifier(KeyboardToolbar(focusedField: focusedField))
    }
}
