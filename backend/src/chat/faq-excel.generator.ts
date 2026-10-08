import ExcelJS from "exceljs";
import * as path from "path";

export async function generateDefaultFaqExcel(targetPath?: string): Promise<string> {
  const filePath = targetPath || path.resolve(process.cwd(), "faq_template.xlsx");
  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet("FAQ");

  sheet.columns = [
    { header: "Category", key: "category", width: 20 },
    { header: "Question", key: "question", width: 45 },
    { header: "Answer", key: "answer", width: 60 },
    { header: "Keywords", key: "keywords", width: 35 },
  ];

  sheet.getRow(1).font = { bold: true };

  const defaultEntries = [
    {
      category: "Class Info",
      question: "What should I wear to my first pole class?",
      answer: "Wear comfortable shorts and a tank top or sports bra. Skin contact with the pole helps with grip! Avoid applying oils or body lotions on the day of class.",
      keywords: "wear, clothes, attire, beginner, outfit, dress",
    },
    {
      category: "Pricing & Packages",
      question: "How do package credits work?",
      answer: "You can purchase class credit packages from the Packages tab. Once your payment proof screenshot is verified by the studio, credits will appear in your account and can be used to book classes directly.",
      keywords: "packages, pricing, credits, cost, purchase, payment",
    },
    {
      category: "Bookings & Trials",
      question: "How can I book a trial class?",
      answer: "Navigate to the Schedule page, select an upcoming Trial class slot, choose Walk-in or Package booking, and submit your reservation.",
      keywords: "trial, book, schedule, first time, new student",
    },
    {
      category: "Studio Policies",
      question: "What is the studio cancellation policy?",
      answer: "Classes can be cancelled up to 12 hours in advance for a full credit refund. Late cancellations or no-shows forfeit the class credit.",
      keywords: "cancellation, cancel, refund, policy, reschedule",
    },
    {
      category: "Studio Location & Hours",
      question: "Where is Dreamtopia located and what are opening hours?",
      answer: "Dreamtopia is located in Yangon. Our reception and studio floors are open from 8:00 AM to 8:30 PM daily for scheduled classes and practice sessions.",
      keywords: "location, address, hours, time, where, open",
    },
  ];

  for (const entry of defaultEntries) {
    sheet.addRow(entry);
  }

  await workbook.xlsx.writeFile(filePath);
  return filePath;
}
