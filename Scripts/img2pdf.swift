#!/usr/bin/swift
import Foundation
import CoreGraphics
import ImageIO

let fileManager = FileManager.default
let currentDir = fileManager.currentDirectoryPath
var folderName = URL(fileURLWithPath: currentDir).lastPathComponent
if folderName.isEmpty || folderName == "/" { folderName = "Merged" }
let outputPdfPath = currentDir + "/\(folderName).pdf"

let validExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff", "bmp", "webp"]

do {
    let files = try fileManager.contentsOfDirectory(atPath: currentDir)
    let imageFiles = files.filter { validExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
                          .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    if imageFiles.isEmpty {
        print("❌ 錯誤：當前目錄下沒有找到支援的圖片檔案！")
        exit(1)
    }

    print("📂 找到 \(imageFiles.count) 個圖片檔案，開始進行『等寬無損』合併...")

    let outURL = URL(fileURLWithPath: outputPdfPath) as CFURL
    guard let pdfContext = CGContext(outURL, mediaBox: nil, nil) else {
        print("❌ 無法建立 PDF 檔案")
        exit(1)
    }

    let fixedWidth: CGFloat = 595.28

    for fileName in imageFiles {
        let fileURL = URL(fileURLWithPath: currentDir + "/" + fileName) as CFURL

        guard let imageSource = CGImageSourceCreateWithURL(fileURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            print("  ⚠️ 無法解析圖片內容，跳過: \(fileName)")
            continue
        }

        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        if imgW > 0 {
            let aspectRatio = imgH / imgW
            let newHeight = fixedWidth * aspectRatio

            var pageRect = CGRect(x: 0, y: 0, width: fixedWidth, height: newHeight)

            // 修正：使用正確的 CoreGraphics 頁面建立語法
            pdfContext.beginPage(mediaBox: &pageRect)

            // 將圖片繪製入該頁面
            pdfContext.draw(cgImage, in: pageRect)

            // 修正：使用正確的結束頁面語法
            pdfContext.endPage()

            print("  └─ 已完美對齊並加入: \(fileName)")
        }
    }

    pdfContext.closePDF()
    print("\n✅ 合併成功！輸出檔案：\(folderName).pdf")

} catch {
    print("❌ 發生錯誤: \(error)")
}
