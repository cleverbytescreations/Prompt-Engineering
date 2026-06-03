# Use Cases - Restricted Social Platform for ICA Members

---

## 1. USER MANAGEMENT & ACCESS CONTROL MODULE

### ICA Legal Office (Admin)

- Create / manage organizations
- Invite users via coupon/invite system
- Assign roles (Admin / Moderator / Member)
- Deactivate / restrict users
- Monitor platform usage

### Moderator

- Access moderation dashboard
- Review user submissions (questions, documents, news)
- Approve / reject / request changes
- Flag inappropriate content

### Member (ICA Organization Users)

- Register via invite
- Login / logout
- Manage profile (basic)
- View role-based content

---

## 2. KNOWLEDGE REPOSITORY (LEGAL DATABASE MODULE)

### Member / Contributor

- Upload legal documents (PDF / link)
- Add metadata:
  - Country
  - Law type (Act, Constitution, Tax, etc.)
- View repository (browse / search)
- Download documents

### Moderator

- Review uploaded documents
- Validate authenticity
- Approve / reject submissions
- Edit metadata if needed

### Admin

- Manage document categories / taxonomy
- Monitor repository growth

### AI (Supporting Use Cases)

- OCR processing for scanned PDFs
- Extract structured content from documents
- Index documents into vector DB
- Enable semantic search across laws

---

## 3. QUESTION & ANSWER MODULE (CORE FEATURE)

### Member

- Ask questions
- View own question history
- Browse existing Q&A
- Participate in discussions (optional phase)

### Moderator

- Review submitted questions
- Approve / reject questions
- Route to legal experts if needed
- Ensure quality and relevance

### ICA Legal Office / Experts

- Answer questions
- Provide authoritative interpretations
- Convert answers into reusable knowledge

### AI (Supporting)

- Suggest answers using RAG / flag inappropriate questions for manual review (Moderator)
- Retrieve relevant legal documents
- Summarize answers

### Special Use Case

- Approved Q&A becomes part of **knowledge base (self-learning system)**

---

## 4. NEWS & UPDATES MODULE

### Member / Contributor

- Submit news / updates
- Share policy changes or legal developments
- Create posts (insights, updates)
- Share knowledge
- Engage in discussions
- View social feed

### Moderator

- Categorize news / posts

### Admin / Internal Team

- Post official updates
- Curate daily news

---

## 5. CONTRIBUTION & VALIDATION WORKFLOW MODULE

### Member / Contributor

- Submit:
  - Documents
  - Questions
  - News / Posts

### Moderator

- Review all submissions
- Approve / reject questions

### System Use Cases

- Maintain audit trail
- Version control for content
- Status tracking (Pending / Approved / Rejected)

---

## 6. SEARCH & DISCOVERY MODULE

### Member

- Search:
  - Laws *(is there any retraction??)*
  - Questions
  - News
- Filter by:
  - Country
  - Category
  - Date

Note: Concretely, it's asking: should the search for Laws surface whether a law has been retracted, repealed, or replaced? This would be relevant for ICA legal members who need to know if a law they find is still in force.

What this likely needs in the implementation:

A status or retraction_status field on legal documents (e.g., Active, Retracted, Superseded)
Search results should surface this status prominently
Filtering by retraction status (e.g., exclude retracted laws by default)

#### What's missing:
No retraction_status or is_retracted field on the document model
No retraction-related filter in /search or /documents
The moderation flow (Approve/Reject/Request Changes) has no "Retract" action for already-published laws
Recommendation: This needs a decision before Module 5 (Repository) or Module 11 (Search) are built. Options:

Add a status field on documents: Active | Retracted | Superseded — surfaced in search results and filterable
Treat retraction as a new moderation action (post-approval withdrawal)

### AI

- Semantic search (vector-based)
- Contextual retrieval (RAG)
- Suggest related content

---

## 7. MULTI-LANGUAGE MODULE

### Member

- View content in preferred language
- Ask questions in native language

### AI

- Translate:
  - Input → English (processing)
  - Output → user language
- Maintain multilingual knowledge access

---

## 8. ADMIN & MODERATION DASHBOARD

### Admin

- User management
- Content analytics
- Platform configuration
- Monitor AI usage & cost

### Moderator

- Unified moderation queue:
  - Questions
  - Documents
  - News
  - Posts

---

## 9. NOTIFICATION MODULE

### Member

- Receive notifications:
  - Question answered
  - News updates
  - Approval status

---

## 10. AI & DATA PROCESSING MODULE (CORE DIFFERENTIATOR)

### System-Level Use Cases

- Document ingestion pipeline:
  - OCR → chunking → embedding
- RAG-based Q&A
- Knowledge graph evolution
- Content summarization
- Smart recommendations

---

## 11. SECURITY & ACCESS CONTROL

### System Use Cases

- Role-based access control (RBAC)
- Invite-only onboarding
- Organization-level restrictions
- Data privacy enforcement
