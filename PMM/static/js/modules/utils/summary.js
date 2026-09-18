const SECTION_ALIASES = {
    overview: ['overview', 'summary', 'meeting_summary', 'executive_summary'],
    keyPoints: ['key_points', 'key_discussion_points', 'discussion_points', 'key_discussions', 'topics'],
    actionItems: ['action_items', 'actions', 'tasks', 'todos', 'to_dos'],
    decisions: ['decisions', 'decision_points'],
    nextSteps: ['next_steps', 'nextsteps', 'follow_ups', 'followups'],
    risks: ['risks', 'blockers', 'concerns']
};

const cleanText = (value) => {
    if (value === null || value === undefined) return '';
    if (typeof value === 'string') return value.trim();
    if (typeof value === 'number' || typeof value === 'boolean') return String(value);
    if (typeof value === 'object') {
        return Object.entries(value)
            .map(([key, item]) => `${humanizeKey(key)}: ${cleanText(item)}`)
            .filter(Boolean)
            .join(' - ');
    }
    return '';
};

const humanizeKey = (key) => String(key || '')
    .replace(/[_-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\b\w/g, (char) => char.toUpperCase());

const stripCodeFence = (text) => {
    const trimmed = String(text || '').trim();
    const match = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
    return match ? match[1].trim() : trimmed;
};

const normalizeJsonLikeText = (text) => String(text || '')
    .replace(/[\u201c\u201d]/g, '"')
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/\u00a0/g, ' ');

const parseJsonSummary = (summary) => {
    if (!summary) return null;
    if (typeof summary === 'object') return summary;
    const text = normalizeJsonLikeText(stripCodeFence(summary));

    try {
        return JSON.parse(text);
    } catch (_) {
        const start = text.indexOf('{');
        const end = text.lastIndexOf('}');
        if (start !== -1 && end > start) {
            try {
                return JSON.parse(text.slice(start, end + 1));
            } catch (_) {}
        }
    }

    return null;
};

const coerceList = (value) => {
    if (value === null || value === undefined || value === '') return [];
    if (Array.isArray(value)) return value.map(cleanText).filter(Boolean);
    if (typeof value === 'object') return Object.values(value).map(cleanText).filter(Boolean);
    return String(value)
        .split(/\n+/)
        .map((line) => line.replace(/^[-*•\d.)\s]+/, '').trim())
        .filter(Boolean);
};

const findValue = (source, aliases) => {
    if (!source || typeof source !== 'object') return undefined;
    for (const alias of aliases) {
        if (Object.prototype.hasOwnProperty.call(source, alias)) return source[alias];
    }
    const normalized = Object.entries(source).find(([key]) =>
        aliases.includes(String(key).toLowerCase().replace(/[\s-]+/g, '_'))
    );
    return normalized ? normalized[1] : undefined;
};

export const parseSummaryContent = (summary) => {
    const data = parseJsonSummary(summary);
    if (!data) {
        return {
            isStructured: false,
            overview: cleanText(summary),
            keyPoints: [],
            actionItems: [],
            decisions: [],
            nextSteps: [],
            risks: []
        };
    }

    const parsed = {
        isStructured: true,
        overview: cleanText(findValue(data, SECTION_ALIASES.overview)),
        keyPoints: coerceList(findValue(data, SECTION_ALIASES.keyPoints)),
        actionItems: coerceList(findValue(data, SECTION_ALIASES.actionItems)),
        decisions: coerceList(findValue(data, SECTION_ALIASES.decisions)),
        nextSteps: coerceList(findValue(data, SECTION_ALIASES.nextSteps)),
        risks: coerceList(findValue(data, SECTION_ALIASES.risks))
    };
    if (!parsed.overview && !parsed.keyPoints.length && !parsed.actionItems.length &&
        !parsed.decisions.length && !parsed.nextSteps.length && !parsed.risks.length) {
        parsed.overview = cleanText(data);
    }
    return parsed;
};

export const formatSummaryAsPlainText = (summary, recording = {}) => {
    const parsed = parseSummaryContent(summary);
    const lines = ['Meeting Summary', ''];

    const date = recording.meeting_date || recording.created_at;
    if (date || recording.audio_duration || recording.participants) {
        lines.push('Meeting Information');
        if (date) lines.push(`Date: ${date}`);
        if (recording.audio_duration) lines.push(`Duration: ${recording.audio_duration}`);
        if (recording.participants) lines.push(`Participants: ${recording.participants}`);
        lines.push('');
    }

    const addText = (title, text) => {
        if (!text) return;
        lines.push(title, text, '');
    };
    const addList = (title, items, marker = '-') => {
        if (!items || !items.length) return;
        lines.push(title, ...items.map((item) => `${marker} ${item}`), '');
    };

    addText('Summary', parsed.overview);
    addList('Key Discussion Points', parsed.keyPoints);
    addList('Action Items', parsed.actionItems, '[ ]');
    addList('Decisions', parsed.decisions);
    addList('Next Steps', parsed.nextSteps);
    addList('Risks', parsed.risks);
    lines.push('Generated by AI Meeting Assistant');

    return lines.join('\n').replace(/\n{3,}/g, '\n\n').trim();
};
