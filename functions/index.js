const functions = require("firebase-functions");
const admin = require("firebase-admin");
const cors = require("cors")({ origin: true });

admin.initializeApp();

// Configuration for owner authentication
const OWNER_PIN = process.env.OWNER_PIN || "123456";
const AUTHORIZED_OWNER_PHONE = process.env.AUTHORIZED_OWNER_PHONE || "+919430801489";

exports.ownerLogin = functions.https.onRequest((req, res) => {
  cors(req, res, async () => {
    if (req.method !== "POST") {
      return res.status(405).json({ error: "Method Not Allowed" });
    }

    try {
      const { mobileNumber, pin } = req.body || {};

      if (!mobileNumber || !pin) {
        return res.status(400).json({ 
          error: "Both Mobile Number and Security PIN are required." 
        });
      }

      const cleanDigits = String(mobileNumber).trim().replace(/\D/g, "");
      const formattedPhone = String(mobileNumber).trim().startsWith("+")
        ? String(mobileNumber).trim()
        : `+91${cleanDigits.length === 10 ? cleanDigits : cleanDigits.slice(-10)}`;

      // Strict verification against backend credentials
      if (String(pin).trim() !== OWNER_PIN || formattedPhone !== AUTHORIZED_OWNER_PHONE) {
        return res.status(401).json({ 
          error: "Invalid Mobile Number or Security PIN." 
        });
      }

      // Look up or create the Firebase Auth user for the verified owner
      let userRecord;
      try {
        userRecord = await admin.auth().getUserByPhoneNumber(formattedPhone);
      } catch (err) {
        if (err.code === "auth/user-not-found") {
          userRecord = await admin.auth().createUser({
            phoneNumber: formattedPhone,
            displayName: "Gas Agency Owner",
          });
        } else {
          throw err;
        }
      }

      // Attach custom claims required by Firestore Security Rules
      await admin.auth().setCustomUserClaims(userRecord.uid, {
        phone_number: formattedPhone,
        role: "owner"
      });

      // Ensure /owners/{uid} document exists in Firestore
      const db = admin.firestore();
      const ownerDocRef = db.collection("owners").doc(userRecord.uid);
      const ownerDoc = await ownerDocRef.get();
      if (!ownerDoc.exists) {
        await ownerDocRef.set({
          uid: userRecord.uid,
          phoneNumber: formattedPhone,
          agencyName: "Gas Agency Management",
          role: "owner",
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        });
      }

      // Generate Firebase Custom Token
      const customToken = await admin.auth().createCustomToken(userRecord.uid, {
        phone_number: formattedPhone,
        role: "owner"
      });

      return res.status(200).json({
        success: true,
        customToken: customToken,
        uid: userRecord.uid
      });
    } catch (error) {
      console.error("Owner login authentication error:", error);
      return res.status(500).json({ 
        error: "Authentication service error. Please try again." 
      });
    }
  });
});
